//
//  PikardApp.swift
//  Pikard
//
//  Created by Yuriy Tatar on 23/5/26.
//

// PikardApp.swift
import SwiftUI

@main
struct PikardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }  // placeholder — keeps `App` happy with no windows
    }
}
