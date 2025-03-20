import SwiftUI
import RealityKit
import ARKit

struct ContentView: View {
    // State variables to track position
    @State private var rotationAngle: Float = 0.0
    @State private var x: Double = 0.0
    @State private var y: Double = 0.0
    @State private var z: Double = 0.0
    @State private var score: Int = 0
    
    @State private var audio: AudioFileResource?
    @State private var subscriptions = [EventSubscription]() // Keep track of subscriptions
    
    var body: some View {
        ZStack {
            // AR View takes most of the screen
            ARContentView(x: $x, y: $y, z: $z, audio: $audio, subscriptions: $subscriptions, score: $score)
                .edgesIgnoringSafeArea(.all)
            
            // Score display at the top
            VStack {
                Text("Score: \(score)")
                    .font(.title)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.top)
                
                Spacer()
                
                // Control panel at the bottom
                VStack(spacing: 15) {
                    Text("Teapot Position Controls")
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
    @Binding var score: Int
    
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
            
            // Load and place the teapot
            if let teapot = try? await ModelEntity(named: "teapot") {
                teapot.position = [0, 0, -0.5] // 50cm in front of the camera
                // Generate default collision shapes for all mesh parts
                teapot.physicsBody? = PhysicsBodyComponent()
                teapot.physicsBody?.mode = .dynamic
                teapot.generateCollisionShapes(recursive: false)
                teapot.name = "teapot" // Set a name to identify it later
                anchor.addChild(teapot)
                
                // Optional: Add spatial audio component
                teapot.spatialAudio = SpatialAudioComponent(directivity: .beam(focus: 0.75))
                
                // Enable tapping on the teapot
                teapot.components.set(InputTargetComponent())
            }
            
            // Load and place the TV
            if let tv = try? await ModelEntity(named: "tv_retro") {
                tv.position = [0, 0, 1] // Position to the right of the teapot
                // tv.scale = [0.1, 0.1, 0.1] // Scale down the TV as these models can be large
                // Generate default collision shapes for all mesh parts
                tv.physicsBody? = PhysicsBodyComponent()
                tv.physicsBody?.mode = .dynamic
                tv.generateCollisionShapes(recursive: false)
                tv.name = "tv" // Set a name to identify it later
                
                let orbit = OrbitAnimation(duration: 5.0,
                                                               axis: [1,0,0],
                                                     startTransform: tv.transform,
                                                         bindTarget: .transform,
                                                         repeatMode: .repeat)
                
                if let animation = try? AnimationResource.generate(with: orbit) {
                                    tv.playAnimation(animation)
                                }
                
                anchor.addChild(tv)
                
                // Add spatial audio component to TV as well
                tv.spatialAudio = SpatialAudioComponent(directivity: .beam(focus: 0.75))
                
                // Enable tapping on the TV
                tv.components.set(InputTargetComponent())
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
                
                // Check which entities are colliding
                let entityA = event.entityA
                let entityB = event.entityB
                
                // Only increment score if teapot and tv collide with each other
                let teapotAndTvCollision = (entityA.name == "teapot" && entityB.name == "tv") ||
                                          (entityA.name == "tv" && entityB.name == "teapot")
                
                if teapotAndTvCollision {
                    // Increment score on the main thread
                    DispatchQueue.main.async {
                        self.score += 1
                        print("Score increased to: \(self.score)")
                    }
                }
                
                if let ar = self.audio {
                    // Play sound on any of our models when they collide
                    let collidedEntity = entityA.name == "teapot" || entityA.name == "tv" ? entityA :
                                         entityB.name == "teapot" || entityB.name == "tv" ? entityB : nil
                    
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
            // Update block
            if let anchor = content.entities.first as? AnchorEntity {
                // Only update the teapot position
                for child in anchor.children {
                    if child.name == "teapot", let teapot = child as? ModelEntity {
                        // Update teapot position based on sliders
                        teapot.transform.translation = [Float(x), Float(y), Float(z)]
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
