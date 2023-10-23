//
//  ContentView.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 21/10/23.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                
            } detail: {
                HomeView()
            }
        } else {
            TabContainerView()
        }
    }
}

#Preview {
    ContentView()
}
