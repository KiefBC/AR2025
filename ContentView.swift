struct ARContentView: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var z: Double
    @Binding var audio: AudioFileResource?
    @Binding var subscriptions: [EventSubscription]
    @Binding var score: Int
    
    // Track the last collision time to prevent double counting
    @State private var lastCollisionTime: TimeInterval = 0
    
    var body: some View {
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
                // Get current time
                let currentTime = Date().timeIntervalSince1970
                
                // Only count collision if it's been at least 0.5 seconds since the last one
                // This prevents double counting the same physical collision
                if currentTime - self.lastCollisionTime > 0.5 {
                    // Increment score on the main thread
                    DispatchQueue.main.async {
                        self.score += 1
                        print("Score increased to: \(self.score)")
                    }
                    // Update the last collision time
                    self.lastCollisionTime = currentTime
                } else {
                    print("Ignoring duplicate collision event")
                }
            }
        })
    }
} 