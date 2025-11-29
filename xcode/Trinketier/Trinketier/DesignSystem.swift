import SwiftUI

// MARK: - Colors
extension Color {
    static let retroYellow = Color(hex: "FFD700") // Bright Yellow
    static let retroPink = Color(hex: "FFB6C1")   // Light Pink
    static let retroBlue = Color(hex: "87CEEB")   // Sky Blue
    static let retroGreen = Color(hex: "90EE90")  // Light Green
    static let retroWhite = Color(hex: "FDFDFD")  // Off White
    static let retroBlack = Color(hex: "121212")  // Off Black
    static let retroBeige = Color(hex: "F5F5DC")  // Beige
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Modifiers

struct RetroCardModifier: ViewModifier {
    var backgroundColor: Color = .retroWhite
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(backgroundColor)
            .border(Color.retroBlack, width: 2)
    }
}

extension View {
    func retroCard(backgroundColor: Color = .retroWhite) -> some View {
        self.modifier(RetroCardModifier(backgroundColor: backgroundColor))
    }
}

// MARK: - Button Style

struct RetroButtonStyle: ButtonStyle {
    var backgroundColor: Color = .retroBlue
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? backgroundColor.opacity(0.8) : backgroundColor)
    }
}

struct RetroWindowControls: View {
    private var window: NSWindow? {
        NSApp.keyWindow ?? NSApplication.shared.windows.first
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Close (Red)
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Rectangle()
                    .fill(Color.retroPink)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.retroBlack)
                    )
            }
            .frame(width: 34, height: 34)
            .buttonStyle(.plain)
            
            Rectangle()
                .fill(Color.retroBlack)
                .frame(width: 2)
            // Maximize (Yellow)
            Button(action: { window?.zoom(nil) }) {
                Rectangle()
                    .fill(Color.retroYellow)
                    .overlay(
                        Rectangle()
                            .stroke(Color.retroBlack, lineWidth: 2)
                            .frame(width: 12, height: 12)
                    )
            }
            .frame(width: 34, height: 34)
            .buttonStyle(.plain)
            Rectangle()
                .fill(Color.retroBlack)
                .frame(width: 2)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            
            // Use borderless to remove system rounded corners
            window.styleMask = [.borderless, .resizable, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            
            // Set minimum window size to prevent toolbar clipping
            window.minSize = NSSize(width: 800, height: 500)
            
            // Make window transparent so SwiftUI handles the shape
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            
            // Force invalidation to apply changes
            window.invalidateShadow()
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Background

struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 20
            let width = size.width
            let height = size.height
            
            var path = Path()
            
            // Vertical lines
            for x in stride(from: 0, to: width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
            
            // Horizontal lines
            for y in stride(from: 0, to: height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
            
            context.stroke(path, with: .color(.retroBlack.opacity(0.1)), lineWidth: 1)
        }
        .background(Color.retroBeige)
        .ignoresSafeArea()
    }
}
