//
//  CinematiCamApp.swift
//  CinematiCam
//
//  Created by Abhishek Dangol on 1/25/26.
//

import SwiftUI

@main
struct CinematiCamApp: App {
    init() {
        Diagnostics.logStart()
    }

    /// The welcome screens show once; the camera (and its access questions) comes after them
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome {
                ContentView()
            } else {
                WelcomeView { hasSeenWelcome = true }
            }
        }
    }
}
