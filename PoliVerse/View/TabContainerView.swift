//
//  TabContainerView.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 19/10/23.
//

import SwiftUI

struct TabContainerView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "graduationcap")
                }
            Text("WeBeep View")
                .tabItem {
                    Label("WeBeep", systemImage: "books.vertical")
                }
            Text("Calendar and Task View")
                .tabItem {
                    Label("Calendario", systemImage: "calendar.day.timeline.left")
                }
            Text("Search View")
                .tabItem {
                    Label("Cerca", systemImage: "magnifyingglass")
                }
            Text("Profile and Carreer View")
                .tabItem {
                    Label("Carriera", systemImage: "person")
                }
        }    }
}

#Preview {
    TabContainerView()
}
