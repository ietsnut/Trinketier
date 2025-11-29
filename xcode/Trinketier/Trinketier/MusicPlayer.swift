import SwiftUI
import Foundation
import AVFoundation
import Combine

class MusicPlayer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 0.8 {
        didSet {
            audioPlayer?.volume = volume
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    
    override init() {
        super.init()
        loadTrack()
    }
    
    /// Configure the single embedded file here (add it to the app target).
    private func loadTrack() {
        // Change these to match your actual file
        let name = "breakcore"
        let ext = "mp3"
        
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("⚠️ Could not find \(name).\(ext) in bundle")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1     // loop forever
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
        } catch {
            print("⚠️ Failed to load audio: \(error)")
        }
    }
    
    func togglePlayPause() {
        guard let player = audioPlayer else {
            // Try loading again if something went wrong
            loadTrack()
            audioPlayer?.play()
            isPlaying = true
            return
        }
        
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
}
