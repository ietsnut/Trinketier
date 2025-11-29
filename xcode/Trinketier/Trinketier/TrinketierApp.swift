import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseAppCheck
import FirebaseAILogic
import ORSSerial

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
    }
}

class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var userDescription: String = "Not signed in"
    
    private var authHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        FirebaseApp.configure()
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            if let user = user {
                self.isAuthenticated = true
                if let email = user.email, !email.isEmpty {
                    self.userDescription = "Signed in as \(email)"
                } else if user.isAnonymous {
                    self.userDescription = "Signed in anonymously"
                } else {
                    self.userDescription = "Signed in (uid: \(user.uid))"
                }
            } else {
                self.isAuthenticated = false
                self.userDescription = "Not signed in"
            }
        }
    }
    
    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func start() {
        if Auth.auth().currentUser == nil {
            signInAnonymously()
        }
    }
    
    func signInAnonymously() {
        Auth.auth().signInAnonymously { [weak self] result, error in
            if let error = error {
                self?.userDescription = "Anon sign-in failed: \(error.localizedDescription)"
                return
            }
            if let user = result?.user {
                self?.userDescription = "Signed in anonymously (uid: \(user.uid))"
                self?.isAuthenticated = true
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            userDescription = "Sign out failed: \(error.localizedDescription)"
        }
    }
}

class AIService: ObservableObject {
    @Published var lastAIStatus: String = "Idle"
    @Published var isRunning: Bool = false
    
    private let model: TemplateGenerativeModel
    
    init() {
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        self.model = ai.templateGenerativeModel()
    }
    
    private func stripCodeFences(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                let afterNewline = result.index(after: firstNewline)
                result = String(result[afterNewline...])
            } else {
                result = result.replacingOccurrences(of: "```", with: "")
            }
        }
        
        if let lastFenceRange = result.range(of: "```", options: .backwards) {
            result.removeSubrange(lastFenceRange.lowerBound..<result.endIndex)
        }
        
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
    
    func sendPrompt(prompt: String, codeContext: String, completion: @escaping (String?) -> Void) {
        isRunning = true
        lastAIStatus = "Talking to Gemini…"
        
        Task { @MainActor in
            do {
                let response = try await model.generateContent(
                    templateID: "pico-code-assistant-v1-0-0",
                    inputs: [
                        "codeContext": codeContext,
                        "studentPrompt": prompt
                    ]
                )
                
                let generatedRaw = response.text ?? ""
                let generated = stripCodeFences(from: generatedRaw)
                
                if generated.isEmpty {
                    self.lastAIStatus = "AI responded with no usable code."
                    self.isRunning = false
                    completion(nil)
                } else {
                    self.lastAIStatus = "AI updated the code."
                    self.isRunning = false
                    completion(generated)
                }
            } catch {
                self.lastAIStatus = "AI error: \(error.localizedDescription)"
                self.isRunning = false
                completion(nil)
            }
        }
    }
}

class SerialPortController: NSObject, ObservableObject, ORSSerialPortDelegate {
    @Published var selectedPortPath: String?
    @Published var receivedText: String = ""
    @Published var isOpen: Bool = false
    @Published var baudRate: Int = 115200
    
    private var currentPort: ORSSerialPort? {
        ORSSerialPortManager.shared().availablePorts.first { $0.path == selectedPortPath }
    }
    
    func open() {
        guard let port = currentPort else { return }
        if port.isOpen { return }

        port.baudRate = NSNumber(value: baudRate)
        port.parity = .none
        port.numberOfStopBits = 1
        port.usesRTSCTSFlowControl = false
        port.usesDTRDSRFlowControl = false

        port.delegate = self
        port.open()

        // 👇 These lines are the important bit for the Pico/CircuitPython
        port.dtr = true        // Tell the board “terminal is ready”
        port.rts = true        // Often harmless/needed on USB CDC devices

        isOpen = port.isOpen
    }

    
    func close() {
        currentPort?.close()
        isOpen = false
    }
    
    func clear() {
        receivedText = ""
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        if let string = String(data: data, encoding: .utf8) {
            DispatchQueue.main.async {
                self.receivedText.append(string)
            }
        }
    }
    
    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        DispatchQueue.main.async {
            if self.selectedPortPath == serialPort.path {
                self.selectedPortPath = nil
                self.isOpen = false
            }
        }
    }
    
    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        DispatchQueue.main.async {
            if self.selectedPortPath == serialPort.path {
                self.isOpen = true
            }
        }
    }
    
    func serialPortWasClosed(_ serialPort: ORSSerialPort) {
        DispatchQueue.main.async {
            if self.selectedPortPath == serialPort.path {
                self.isOpen = false
            }
        }
    }
}

struct SerialMonitorView: View {
    @StateObject private var controller = SerialPortController()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Serial Monitor")
                    .font(.title2)
                    .bold()
                Spacer()
                Picker("Port", selection: $controller.selectedPortPath) {
                    Text("None").tag(String?.none)
                    ForEach(ORSSerialPortManager.shared().availablePorts, id: \.path) { port in
                        Text(port.name ?? port.path).tag(Optional(port.path))
                    }
                }
                .labelsHidden()
                Picker("Baud", selection: $controller.baudRate) {
                    ForEach([9600, 19200, 38400, 57600, 115200], id: \.self) { rate in
                        Text("\(rate)").tag(rate)
                    }
                }
                .frame(width: 100)
                if controller.isOpen {
                    Text("Connected")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Text("Disconnected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            
            HStack(spacing: 10) {
                Button(controller.isOpen ? "Close Port" : "Open Port") {
                    if controller.isOpen {
                        controller.close()
                    } else {
                        controller.open()
                    }
                }
                .disabled(controller.selectedPortPath == nil)
                
                Button("Clear") {
                    controller.clear()
                }
                
                Spacer()
            }
            
            TextEditor(text: $controller.receivedText)
                .font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.3), width: 1)
                .frame(minHeight: 300)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

@main
struct TrinketierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var aiService = AIService()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(aiService)
        }
        .windowStyle(.titleBar)
        
        WindowGroup("Serial Monitor", id: "serial") {
            SerialMonitorView()
        }
        .windowStyle(.titleBar)
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel
    
    var body: some View {
        Group {
            if auth.isAuthenticated {
                ContentView()
            } else {
                VStack(spacing: 16) {
                    Text("Trinketier – Connect to Workshop")
                        .font(.title)
                    Text(auth.userDescription)
                        .foregroundStyle(.secondary)
                    
                    Button("Sign in anonymously") {
                        auth.signInAnonymously()
                    }
                }
                .padding()
                .frame(minWidth: 400, minHeight: 200)
            }
        }
        .onAppear {
            auth.start()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var aiService: AIService
    @Environment(\.openWindow) private var openWindow
    
    @State private var codeText: String = "# Your Pico code will appear here…\n"
    @State private var status: String = "Looking for Pico…"
    @State private var picoVolumeURL: URL? = nil
    @State private var lastDetectedVolumeName: String? = nil
    @State private var lastLoadedVolumePath: String? = nil
    @State private var isBusy: Bool = false
    @State private var aiPrompt: String = ""
    
    private let volumeScanTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Raspberry Pi Pico Code Editor")
                        .font(.title2)
                        .bold()
                    Text(auth.userDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(picoVolumeURL == nil ? .red : .green)
                
                Text(picoVolumeURL == nil ? "No Pico detected" : "Pico mounted: \(lastDetectedVolumeName ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Describe what you want the Pico to do:")
                    .font(.subheadline)
                HStack(alignment: .top, spacing: 8) {
                    TextEditor(text: $aiPrompt)
                        .font(.system(.body, design: .default))
                        .frame(height: 70)
                        .border(Color.gray.opacity(0.3), width: 1)
                    
                    VStack(spacing: 8) {
                        Button("Send to AI") {
                            aiService.sendPrompt(prompt: aiPrompt, codeContext: codeText) { newCode in
                                guard let newCode = newCode, !newCode.isEmpty else { return }
                                self.codeText = newCode
                                if picoVolumeURL != nil {
                                    saveCodeToPico()
                                }
                            }
                        }
                        .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isRunning)
                        
                        Button("Clear") {
                            aiPrompt = ""
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Text(aiService.lastAIStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            HStack(spacing: 10) {
                Button("Reload from Pico") {
                    loadCodeFromPico()
                }
                .disabled(picoVolumeURL == nil || isBusy || aiService.isRunning)
                
                Button("Upload to Pico") {
                    saveCodeToPico()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(picoVolumeURL == nil || isBusy || aiService.isRunning)
                
                Button("Open Serial Monitor") {
                    openWindow(id: "serial")
                }
                
                Spacer()
                
                if isBusy || aiService.isRunning {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            TextEditor(text: $codeText)
                .font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.3), width: 1)
                .frame(minHeight: 300)
            
            HStack {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 500)
        .onAppear {
            scanForPicoVolume()
        }
        .onReceive(volumeScanTimer) { _ in
            scanForPicoVolume()
        }
    }
    
    private func scanForPicoVolume() {
        let fm = FileManager.default
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        
        guard let volumeURLs = try? fm.contentsOfDirectory(at: volumesURL,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles]) else {
            status = "Unable to scan /Volumes."
            picoVolumeURL = nil
            lastLoadedVolumePath = nil
            return
        }
        
        let knownNames: Set<String> = ["CIRCUITPY", "RPI-RP2", "PICOBOOT"]
        
        var found: URL? = nil
        var foundName: String? = nil
        
        for volume in volumeURLs {
            let name = volume.lastPathComponent
            if knownNames.contains(name.uppercased()) ||
                name.uppercased().contains("PICO") ||
                name.uppercased().contains("RP2") {
                found = volume
                foundName = name
                break
            }
        }
        
        if let found = found {
            if picoVolumeURL == nil || found.path != picoVolumeURL?.path {
                picoVolumeURL = found
                lastDetectedVolumeName = foundName
                status = "Pico detected at /Volumes/\(foundName ?? "Pico")."
                if lastLoadedVolumePath != found.path && !isBusy && !aiService.isRunning {
                    lastLoadedVolumePath = found.path
                    loadCodeFromPico()
                }
            }
        } else {
            picoVolumeURL = nil
            lastDetectedVolumeName = nil
            lastLoadedVolumePath = nil
            status = "Looking for Pico… (plug it in and mount it)"
        }
    }
    
    private func loadCodeFromPico() {
        guard let picoURL = picoVolumeURL else {
            status = "No Pico volume to read from."
            return
        }
        
        let codeURL = picoURL.appendingPathComponent("code.py")
        let fm = FileManager.default
        
        isBusy = true
        defer { isBusy = false }
        
        if !fm.fileExists(atPath: codeURL.path) {
            status = "No code.py found on Pico. A new file will be created on upload."
            return
        }
        
        do {
            let data = try Data(contentsOf: codeURL)
            if let text = String(data: data, encoding: .utf8) {
                codeText = text
                status = "Loaded code.py from Pico."
            } else {
                status = "Failed to decode code.py as UTF-8."
            }
        } catch {
            status = "Error reading code.py: \(error.localizedDescription)"
        }
    }
    
    private func saveCodeToPico() {
        guard let picoURL = picoVolumeURL else {
            status = "No Pico volume to write to."
            return
        }
        
        let codeURL = picoURL.appendingPathComponent("code.py")
        isBusy = true
        
        do {
            let data = codeText.data(using: .utf8) ?? Data()
            try data.write(to: codeURL, options: .atomic)
            status = "Saved code.py to Pico."
        } catch {
            status = "Error writing code.py: \(error.localizedDescription)"
        }
        
        isBusy = false
    }
}
