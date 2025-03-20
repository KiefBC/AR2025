import SwiftUI
import RealityKit
import ARKit
import Combine

struct ContentView: View {
    // State variables to track position
    @State private var rotationAngle: Float = 0.0
    @State private var x: Double = 0.0
    @State private var y: Double = 0.0
    @State private var z: Double = 0.0
    @State private var audio: AudioFileResource?
    @State private var subscriptions = [EventSubscription]() // Keep track of subscriptions
    
    var body: some View {
        ZStack {
            // AR View takes most of the screen
            ARContentView(x: $x, y: $y, z: $z, audio: $audio, subscriptions: $subscriptions)
                .edgesIgnoringSafeArea(.all)
            
            // Control panel at the bottom
            VStack {
                Spacer()
                
                VStack(spacing: 15) {
                    Text("Main Teapot Controls")
                        .font(.headline)
                    
                    HStack {
                        Text("X: \(x, specifier: "%.2f")")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $x, in: -1.0...1.0, step: 0.01)
                    }
                    
                    HStack {
                        Text("Y: \(y, specifier: "%.2f")")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $y, in: -1.0...1.0, step: 0.01)
                    }
                    
                    HStack {
                        Text("Z: \(z, specifier: "%.2f")")
                            .frame(width: 60, alignment: .leading)
                        Slider(value: $z, in: -1.0...1.0, step: 0.01)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(15)
                .padding()
            }
        }
    }
}

// Separate view for the AR content
struct ARContentView: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var z: Double
    @Binding var audio: AudioFileResource?
    @Binding var subscriptions: [EventSubscription]
    
    var body: some View {
        RealityView { content in
            // Create an anchor
            let anchor = AnchorEntity(
                .plane(
                    .horizontal,
                    classification: .any,
                    minimumBounds: SIMD2<Float>(0.2, 0.2)
                )
            )
            
            // Load and place the main teapot
            if let mainTeapot = try? await ModelEntity(named: "teapot") {
                mainTeapot.position = [0, 0, -0.5] // 50cm in front of the camera
                // Generate default collision shapes for all mesh parts
                mainTeapot.physicsBody = PhysicsBodyComponent()
                mainTeapot.physicsBody?.mode = .dynamic
                mainTeapot.generateCollisionShapes(recursive: false)
                mainTeapot.name = "mainTeapot" // Set a name to identify it later
                anchor.addChild(mainTeapot)
                
                // Add spatial audio component
                mainTeapot.spatialAudio = SpatialAudioComponent(directivity: .beam(focus: 0.75))
            }
            
            // Create 3 orbital teapots
            for i in 0..<3 {
                async let teapotModel = ModelEntity(named: "teapot")
                
                // Create an entity to serve as the orbit center
                let orbitEntity = Entity()
                orbitEntity.position = [0, Float(i) * 0.1, -0.5] // Different heights for each orbit
                orbitEntity.name = "orbitCenter\(i)"
                
                if let orbitTeapot = try? await teapotModel {
                    // Position teapot at an offset from center
                    let radius: Float = 0.3 + Float(i) * 0.1 // Different radius for each teapot
                    let angle = Float(i) * (2 * .pi / 3) // Distribute teapots evenly
                    
                    orbitTeapot.position = [radius, 0, 0] // Position relative to orbit center
                    orbitTeapot.scale = [0.6, 0.6, 0.6] // Scale down
                    
                    // Generate default collision shapes for all mesh parts
                    orbitTeapot.physicsBody = PhysicsBodyComponent()
                    orbitTeapot.physicsBody?.mode = .dynamic
                    orbitTeapot.generateCollisionShapes(recursive: false)
                    orbitTeapot.name = "orbitTeapot\(i)" // Set a unique name
                    
                    // Add spatial audio component
                    orbitTeapot.spatialAudio = SpatialAudioComponent(directivity: .beam(focus: 0.75))
                    
                    // Add teapot to orbit entity
                    orbitEntity.addChild(orbitTeapot)
                    
                    // Create orbit animation with different durations
                    let duration = 5.0 - Double(i) * 0.5 // Different speeds: 5s, 4.5s, 4s
                    let orbit = OrbitAnimation(
                        duration: duration,
                        axis: [0, 1, 0], // Rotate around Y axis
                        startTransform: orbitEntity.transform,
                        bindTarget: .transform,
                        repeatMode: .repeat
                    )
                    
                    // Create and play animation
                    if let animation = try? AnimationResource.generate(with: orbit) {
                        orbitEntity.playAnimation(animation)
                    }
                    
                    // Add orbit entity to anchor
                    anchor.addChild(orbitEntity)
                }
            }
            
            // Load the audio resource once
            do {
                let audioFile = try await AudioFileResource(
                    named: "pop.mp3",
                    configuration: .init(
                        shouldLoop: false
                    )
                )
                // Store it in our @State property
                self.audio = audioFile
                print("Audio loaded successfully")
            } catch {
                print("Failed to load audio: \(error)")
            }
            
            // Subscribe to collision events
            self.subscriptions.append(content.subscribe(to: CollisionEvents.Began.self) { event in
                print("Collision detected!")
                if let ar = self.audio {
                    // Check which entities are colliding
                    let entityA = event.entityA
                    let entityB = event.entityB
                    
                    // Play sound on any of our models when they collide
                    let collidedEntity = entityA.name.hasPrefix("mainTeapot") || entityA.name.hasPrefix("orbitTeapot") ? entityA :
                                         entityB.name.hasPrefix("mainTeapot") || entityB.name.hasPrefix("orbitTeapot") ? entityB : nil
                    
                    if let entity = collidedEntity {
                        print("\(entity.name) collision - playing sound")
                        try? entity.stopAllAudio()
                        let playbackController = try? entity.playAudio(ar)
                        playbackController?.gain = 5.0  // Increase volume
                    }
                }
            })
            
            // Add the anchor to the scene
            content.add(anchor)
            
            // Enable camera pass-through with tracking
            content.camera = .spatialTracking
        } update: { content in
            // Update block - only need to update the main teapot based on sliders
            if let anchor = content.entities.first as? AnchorEntity {
                for child in anchor.children {
                    if child.name == "mainTeapot" {
                        // Control main teapot with sliders
                        child.transform.translation = [Float(x), Float(y), Float(z)]
                        
                        // Enable tapping
                        if let modelEntity = child as? ModelEntity {
                            modelEntity.components.set(InputTargetComponent())
                        }
                    } else if child.name.hasPrefix("orbitCenter") {
                        // Find the teapot child to make it tappable
                        for orbitChild in child.children {
                            if orbitChild.name.hasPrefix("orbitTeapot") {
                                if let modelEntity = orbitChild as? ModelEntity {
                                    modelEntity.components.set(InputTargetComponent())
                                }
                            }
                        }
                    }
                }
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { etv in
            print("Tapped!")
            if let ar = audio {
                print("Playing audio")
                try? etv.entity.stopAllAudio()
                let playbackController = try? etv.entity.playAudio(ar)
                playbackController?.gain = 5.0  // Increase volume
                print("Audio playback started with controller: \(playbackController != nil)")
            } else {
                print("Audio resource is nil")
            }
        })
        .edgesIgnoringSafeArea(.all)
    }
} 