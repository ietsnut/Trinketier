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

struct AIResponse: Codable {
    let code: String
    let comment: String?
}

class AIService: ObservableObject {
    @Published var lastAIStatus: String = "Idle"
    @Published var isRunning: Bool = false
    @Published var aiComment: String? = nil
    
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
                
                // Trim whitespace from the response
                var trimmedResponse = generatedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Strip code fences if present (e.g., ```json ... ```)
                if trimmedResponse.hasPrefix("```") {
                    // Remove opening fence and language identifier
                    if let firstNewline = trimmedResponse.firstIndex(of: "\n") {
                        let afterNewline = trimmedResponse.index(after: firstNewline)
                        trimmedResponse = String(trimmedResponse[afterNewline...])
                    }
                    // Remove closing fence
                    if let lastFenceRange = trimmedResponse.range(of: "```", options: .backwards) {
                        trimmedResponse.removeSubrange(lastFenceRange.lowerBound..<trimmedResponse.endIndex)
                    }
                    trimmedResponse = trimmedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                // Try to parse JSON response first
                if trimmedResponse.hasPrefix("{") && trimmedResponse.hasSuffix("}"),
                   let jsonData = trimmedResponse.data(using: .utf8) {
                    do {
                        let aiResponse = try JSONDecoder().decode(AIResponse.self, from: jsonData)
                        // Successfully parsed JSON response
                        self.aiComment = aiResponse.comment
                        let code = aiResponse.code.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if code.isEmpty {
                            self.lastAIStatus = "AI responded with no usable code."
                            self.isRunning = false
                            completion(nil)
                        } else {
                            self.lastAIStatus = "AI updated the code."
                            self.isRunning = false
                            completion(code)
                        }
                        return
                    } catch {
                        print("JSON parsing failed: \(error)")
                        // Fall through to legacy handling
                    }
                }
                
                // Fallback to legacy plain text response
                self.aiComment = nil
                let generated = stripCodeFences(from: trimmedResponse)
                
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
    @Published var selectedPortPath: String? {
        didSet {
            if selectedPortPath != nil {
                cancelDetection()
            }
        }
    }
    @Published var receivedText: String = ""
    @Published var isOpen: Bool = false
    @Published var baudRate: Int = 115200
    private let maxConsoleLines = 100
    
    private var currentPort: ORSSerialPort? {
        ORSSerialPortManager.shared().availablePorts.first { $0.path == selectedPortPath }
    }
    
    private let detectionSignature = "\u{001B}]0;"
    private var isDetecting = false
    private var detectionPorts: [ORSSerialPort] = []
    private var detectionIndex: Int = 0
    private var detectionTimeout: DispatchWorkItem?
    private var detectionBuffer: String = ""
    private var detectionCurrentPort: ORSSerialPort?
    
    override init() {
        super.init()
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
        port.dtr = true
        port.rts = true
        isOpen = port.isOpen
    }
    
    func close() {
        currentPort?.close()
        isOpen = false
    }
    
    func clear() {
        receivedText = ""
    }
    
    func send(text: String) {
        guard let port = currentPort, port.isOpen else { return }
        let textWithNewline = text + "\r\n"
        if let data = textWithNewline.data(using: .utf8) {
            port.send(data)
        }
    }
    
    func autoDetectIfNeeded() {
        if selectedPortPath != nil { return }
        if isDetecting { return }
        startDetection()
    }
    
    private func startDetection() {
        let ports = ORSSerialPortManager.shared().availablePorts
        let usbCandidates = ports.filter { port in
            port.path.contains("tty.usb") || port.path.contains("tty.SLAB") || port.path.contains("tty.usbmodem") || port.path.contains("tty.usbserial")
        }
        detectionPorts = usbCandidates.isEmpty ? ports : usbCandidates
        detectionIndex = 0
        detectionBuffer = ""
        isDetecting = true
        testNextDetectionPort()
    }
    
    private func testNextDetectionPort() {
        detectionTimeout?.cancel()
        detectionTimeout = nil
        
        guard isDetecting else { return }
        
        if detectionIndex >= detectionPorts.count {
            cancelDetection()
            return
        }
        
        let port = detectionPorts[detectionIndex]
        detectionIndex += 1
        
        if port.isOpen {
            testNextDetectionPort()
            return
        }
        
        detectionCurrentPort = port
        port.baudRate = NSNumber(value: baudRate)
        port.parity = .none
        port.numberOfStopBits = 1
        port.usesRTSCTSFlowControl = false
        port.usesDTRDSRFlowControl = false
        port.delegate = self
        port.open()
        port.dtr = true
        port.rts = true
        
        let timeout = DispatchWorkItem { [weak self, weak port] in
            guard let self = self, let port = port else { return }
            if self.isDetecting && self.selectedPortPath == nil && port == self.detectionCurrentPort {
                if port.isOpen {
                    port.close()
                }
                self.detectionCurrentPort = nil
                self.testNextDetectionPort()
            }
        }
        detectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeout)
    }
    
    private func cancelDetection() {
        detectionTimeout?.cancel()
        detectionTimeout = nil
        if let port = detectionCurrentPort, port.isOpen, port.path != selectedPortPath {
            port.close()
        }
        detectionCurrentPort = nil
        detectionPorts = []
        detectionIndex = 0
        detectionBuffer = ""
        isDetecting = false
    }
    
    private func stripControlSequences(_ text: String) -> String {
        // Matches OSC sequences: ESC ] ... (BEL or ESC \)
        // \u{001B} is ESC, \u{0007} is BEL
        let pattern = "\u{001B}\\][^\u{0007}\u{001B}]*(\u{0007}|\u{001B}\\\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        return cleaned
    }
    
    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        if isDetecting && selectedPortPath == nil {
            detectionBuffer.append(string)
            if detectionBuffer.contains(detectionSignature) {
                detectionTimeout?.cancel()
                detectionTimeout = nil
                isDetecting = false
                detectionPorts = []
                detectionIndex = 0
                detectionBuffer = ""
                detectionCurrentPort = nil
                selectedPortPath = serialPort.path
                isOpen = serialPort.isOpen
            } else {
                return
            }
        }
        
        let cleaned = stripControlSequences(string)
        guard !cleaned.isEmpty else { return }
        
        DispatchQueue.main.async {
            self.receivedText.append(cleaned)
            self.trimConsoleToMaxLines()
        }
    }
    
    private func trimConsoleToMaxLines() {
        var newlinesSeen = 0
        var index = receivedText.endIndex
        
        // Walk backwards counting newline characters
        while index > receivedText.startIndex && newlinesSeen <= maxConsoleLines {
            index = receivedText.index(before: index)
            if receivedText[index].isNewline {
                newlinesSeen += 1
            }
        }
        
        // If we don't even have more than maxConsoleLines, don't trim
        guard newlinesSeen > maxConsoleLines else { return }
        
        // We've just crossed one extra newline; trim everything before the next character
        let cutIndex = receivedText.index(after: index)
        receivedText.removeSubrange(receivedText.startIndex..<cutIndex)
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
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel
    
    var body: some View {
        ZStack {
            GridBackground()
            WindowAccessor() // Enable window dragging
            
            Group {
                if auth.isAuthenticated {
                    ContentView()
                } else {
                    VStack(spacing: 24) {
                        Text("Trinketier")
                            .font(.system(size: 48, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.retroBlack)
                        
                        Text("Connect to Workshop")
                            .font(.title2)
                            .fontDesign(.monospaced)
                            .foregroundStyle(Color.retroBlack)
                        
                        Text(auth.userDescription)
                            .font(.footnote)
                            .fontDesign(.monospaced)
                            .foregroundStyle(Color.retroBlack.opacity(0.7))
                        
                        Button("Sign in anonymously") {
                            auth.signInAnonymously()
                        }
                        .buttonStyle(RetroButtonStyle(backgroundColor: .retroYellow))
                    }
                    .padding(40)
                    .retroCard(backgroundColor: .retroWhite)
                    .frame(maxWidth: 500)
                }
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(Color.retroBlack, lineWidth: 4)
                .ignoresSafeArea()
        )
        .onAppear {
            auth.start()
        }
    }
}

struct WindowToolbar: View {
    @ObservedObject var auth: AuthViewModel
    @ObservedObject var serialController: SerialPortController
    var picoVolumeURL: URL?
    var lastDetectedVolumeName: String?
    @ObservedObject var musicPlayer: MusicPlayer
    
    var body: some View {
        HStack(spacing: 0) {
            RetroWindowControls()
            
            Spacer()
            
            HStack(spacing: 0) {

                
                
                Rectangle()
                    .fill(Color.retroBlack)
                    .frame(width: 2)
                
                // Mini Music Player
                HStack(spacing: 0) {
                    
                    Button(action: {
                        musicPlayer.togglePlayPause()
                    }) {
                        Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 12, height: 12)
                            
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 2)
                    .padding(6)
                    
                    Rectangle()
                        .fill(Color.retroBlack)
                        .frame(width: 2)
                    
                    RetroVolumeSlider(value: $musicPlayer.volume)
                }
                
                Rectangle()
                    .fill(Color.retroBlack)
                    .frame(width: 2)
                
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(Color.retroBlack, lineWidth: 2)
                        .background(Circle().fill(auth.isAuthenticated ? Color.retroGreen : Color.retroPink))
                        .frame(width: 12, height: 12)
                    
                    Text(auth.isAuthenticated ? "Logged In" : "Guest")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxHeight: .infinity)
                
                
                Rectangle()
                    .fill(Color.retroBlack)
                    .frame(width: 2)
                // Pico Status
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(Color.retroBlack, lineWidth: 2)
                        .background(Circle().fill(picoVolumeURL == nil ? Color.retroPink : Color.retroGreen))
                        .frame(width: 12, height: 12)
                    
                    Text(picoVolumeURL == nil ? "No Pico" : "Connected: \(lastDetectedVolumeName ?? "Pico")")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                }
                

                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 34) // Force toolbar height to match buttons
        .background(Color.retroBeige)
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundStyle(Color.retroBlack),
            alignment: .bottom
        )
    }
}

struct ContentView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var aiService: AIService
    
    @State private var codeText: String = "# Your Pico code will appear here…\n"
    @State private var status: String = "Looking for Pico…"
    @State private var picoVolumeURL: URL? = nil
    @State private var lastDetectedVolumeName: String? = nil
    @State private var lastLoadedVolumePath: String? = nil
    @State private var isBusy: Bool = false
    @State private var aiPrompt: String = ""
    @State private var serialInput: String = ""
    @StateObject private var serialController = SerialPortController()
    @StateObject private var musicPlayer = MusicPlayer()
    
    private let volumeScanTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            WindowToolbar(
                auth: auth,
                serialController: serialController,
                picoVolumeURL: picoVolumeURL,
                lastDetectedVolumeName: lastDetectedVolumeName,
                musicPlayer: musicPlayer       // 👈 new parameter
            )
            
            VSplitView {
                // Top: Split view for AI Assistant and Serial Console
                HSplitView {
                    // AI Assistant Panel
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("AI Assistant")
                                .font(.headline)
                                .fontDesign(.monospaced)
                            Spacer()
                            Text(aiService.lastAIStatus)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.retroBlue.opacity(0.3))
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(height: 2)
                        
                        // Content
                        TextEditor(text: $aiPrompt)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.retroWhite)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .disabled(aiService.isRunning)
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(height: 2)
                        
                        // AI Comment (if present)
                        if let comment = aiService.aiComment, !comment.isEmpty {
                            VStack(spacing: 0) {
                                Text(comment)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.retroBlack.opacity(0.8))
                                    .padding(8)
                                    .padding(.leading, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.retroBlue)
                                
                                Rectangle()
                                    .fill(Color.retroBlack)
                                    .frame(height: 2)
                            }
                        }
                        
                        // Buttons
                        HStack(spacing: 0) {
                            Button("Program") {
                                aiService.sendPrompt(prompt: aiPrompt, codeContext: codeText) { newCode in
                                    guard let newCode = newCode, !newCode.isEmpty else { return }
                                    self.codeText = newCode
                                    if picoVolumeURL != nil {
                                        saveCodeToPico()
                                    }
                                }
                            }
                            .buttonStyle(RetroButtonStyle(backgroundColor: .retroYellow))
                            .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isRunning)
                            
                            Rectangle()
                                .fill(Color.retroBlack)
                                .frame(width: 2)
                            
                            Button("Clear") {
                                aiPrompt = ""
                                aiService.aiComment = nil
                            }
                            .buttonStyle(RetroButtonStyle(backgroundColor: .retroPink))
                            .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiService.isRunning)
                            
                            Rectangle()
                                .fill(Color.retroBlack)
                                .frame(width: 2)
                            
                            Spacer()
                        }
                        .frame(height: 33)
                        .background(Color.retroWhite)
                    }
                    .overlay(Rectangle().stroke(Color.retroBlack, lineWidth: 2))
                    
                    // Serial Console Panel
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Serial Console")
                                .font(.headline)
                                .fontDesign(.monospaced)
                            Spacer()
                            Text(serialController.isOpen ? "Connected" : "Disconnected")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 4)
                        }
                        .padding(8)
                        .background(Color.retroGreen.opacity(0.3))
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(height: 2)
                        
                        // Content
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(serialController.receivedText.trimmingCharacters(in: .newlines))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .textSelection(.enabled)
                                    .id("SerialBottom")
                            }
                            .onChange(of: serialController.receivedText) { _ in
                                proxy.scrollTo("SerialBottom", anchor: .bottom)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.retroWhite)
                        }
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(height: 2)
                        
                        // Buttons
                        HStack(spacing: 0) {
                            TextField("Send to Pico...", text: $serialInput)
                                .font(.system(.body, design: .monospaced))
                                .textFieldStyle(.plain)
                                .padding(8)
                                .onSubmit {
                                    serialController.send(text: serialInput)
                                    serialInput = ""
                                }
                            
                            Rectangle()
                                .fill(Color.retroBlack)
                                .frame(width: 2)
                            
                            Button("Send") {
                                serialController.send(text: serialInput)
                                serialInput = ""
                            }
                            .buttonStyle(RetroButtonStyle(backgroundColor: .retroGreen))
                            .disabled(serialInput.isEmpty || !serialController.isOpen)
                            
                            Rectangle()
                                .fill(Color.retroBlack)
                                .frame(width: 2)

                            Button("Clear") {
                                serialController.clear()
                            }
                            .buttonStyle(RetroButtonStyle(backgroundColor: .retroPink))
                        }
                        .background(Color.retroWhite)
                        .frame(height: 33)
                        
                        
                    }
                    .overlay(Rectangle().stroke(Color.retroBlack, lineWidth: 2))
                }
                
                // Code Editor Panel
                VStack(spacing: 0) {
                    // Content
                    CodeEditor(text: $codeText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .disabled(aiService.isRunning)
                    
                    Rectangle()
                        .fill(Color.retroBlack)
                        .frame(height: 2)
                    
                    // Buttons
                    HStack(spacing: 0) {
                        
                        Button(action: {
                            if let window = NSApp.keyWindow,
                               let firstResponder = window.firstResponder as? NSTextView {
                                firstResponder.undoManager?.undo()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Undo")
                            }
                        }
                        .buttonStyle(RetroButtonStyle(backgroundColor: .retroWhite))
                        .keyboardShortcut("z", modifiers: [.command])
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(width: 2)
                        
                        Button("Upload") {
                            saveCodeToPico()
                        }
                        .buttonStyle(RetroButtonStyle(backgroundColor: .retroGreen))
                        .keyboardShortcut("s", modifiers: [.command])
                        .disabled(picoVolumeURL == nil || isBusy || aiService.isRunning)
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(width: 2)
                        
                        Button("Reload") {
                            loadCodeFromPico()
                        }
                        .buttonStyle(RetroButtonStyle(backgroundColor: .retroBlue))
                        .disabled(picoVolumeURL == nil || isBusy || aiService.isRunning)
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(width: 2)
                        
                        
                        
                        Button("Reset") {
                            newCodeOnPico()
                        }
                        .buttonStyle(RetroButtonStyle(backgroundColor: .retroPink))
                        .disabled(picoVolumeURL == nil || isBusy || aiService.isRunning)
                        
                        Rectangle()
                            .fill(Color.retroBlack)
                            .frame(width: 2)
                        
                        if isBusy || aiService.isRunning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .padding(8)
                        } else {
                            Text(status)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        
                        Spacer()
                    }
                    .frame(height: 33)
                    .background(Color.retroWhite)
                }
                .overlay(Rectangle().stroke(Color.retroBlack, lineWidth: 2))
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            scanForPicoVolume()
            serialController.autoDetectIfNeeded()
        }
        .onReceive(volumeScanTimer) { _ in
            scanForPicoVolume()
            serialController.autoDetectIfNeeded()
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
            status = "Saved code to Pico."
        } catch {
            status = "Error writing code.py: \(error.localizedDescription)"
        }
        
        isBusy = false
    }
    
    private func newCodeOnPico() {
        codeText = ""
        saveCodeToPico()
        status = "Reset code on Pico."
    }
}
