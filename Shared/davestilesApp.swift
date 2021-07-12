//
//  davestilesApp.swift
//  Shared
//
//  Created by The App Studio LLC on 6/14/21.
//

import SwiftUI

@main
struct davestilesApp: App {
	
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
