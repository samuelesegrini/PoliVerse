//
//  HomeView.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 21/10/23.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack{
            VStack(alignment: .leading){
                ScrollView {
                    if sizeClass == .compact{
                        header()
                    }
                                        
                    ScrollView(.horizontal) {
                        HStack{
                            //TODO: get the course from the server and iterate throught the course list
                            ForEach(0...10, id: \.self){ course in
                                courseCard(courseName: "Architetture dei Calcolatori e dei Sistemi Operativi", imageName: course)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaPadding(.horizontal)
        }
    }
    @ViewBuilder
    func header() -> some View {
        HStack{
            VStack(alignment: .leading, spacing: 0){
                Text("Matr. 986617")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .minimumScaleFactor(0.4)
                Text("Hey, Samuele Segrini")
                    .font(.title2)
                    .bold()
                    .fontDesign(.rounded)
                    .minimumScaleFactor(0.4)
            }
            Spacer()
            Image(.profile)
                .resizable()
                .scaledToFit()
                .clipShape(
                    Circle()
                )
        }
        .frame(height: 50)
    }
    @ViewBuilder
    func courseCard(courseName : String, imageName: Int) -> some View {
        ZStack{
            RoundedRectangle(cornerRadius: 50)
                .foregroundStyle(.ultraThickMaterial)
            
            RoundedRectangle(cornerRadius: 35)
                .foregroundStyle(.background)
                .overlay(alignment: .bottomLeading) {
                    ZStack{
                        Rectangle()
                            .foregroundStyle(.ultraThickMaterial)
                            .clipShape(RoundedCornersShape(corners: [.topRight], radius: 50))
                            .frame(width: 130,height: 70)
                            .overlay {
                                CurvedRightTriangle(radius: 50)
                                    .offset(x: 64, y: -12)
                                    .foregroundStyle(.ultraThickMaterial)
                                    .frame(width: 105,height: 95)
                                CurvedRightTriangle(radius: 50)
                                    .offset(x: -65, y: -82)
                                    .foregroundStyle(.ultraThickMaterial)
                                    .frame(width: 105,height: 95)
                            }
                        
                    }
                }
                .padding()
            
            VStack{
                Text(courseName)
                    .font(.title3)

                /// Course Button
                HStack{
                    Menu {
                        Button("Vedi Forum", action: {})
                        Button("Apri Orario", action: {})
                        Button {
                            
                        } label: {
                            Label("Preferito", systemImage: "star.fill")
                        }
                    } label: {
                        ZStack{
                            Circle()
                                .foregroundStyle(.gray.secondary)
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .bold()
                                .foregroundStyle(.white)
                        }
                    }
                    /// Like Button
                    Button{} label: {
                        ZStack{
                            Circle()
                                .foregroundStyle(.background)
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.primary)
                                .font(.system(size: 20))
                                .bold()
                        }
                    }
                    Spacer(minLength: 25)
                    Button{} label: {
                        ViewThatFits(in: .horizontal) {
                            ZStack{
                                Capsule()
                                    .foregroundStyle(Color.accentColor)
                                HStack{
                                    Text("Corso")
                                        .font(.subheadline)
                                        .bold()
                                        .padding(.leading, 10)
                                        .foregroundStyle(.background)
                                        .minimumScaleFactor(0.6)
                                        .frame(maxHeight: 45)
                                    Spacer()
                                    ZStack{
                                        Circle()
                                            .foregroundStyle(.background)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 20))
                                    }
                                    .padding(5)
                                }
                                
                            }
                            .frame(width: 150)
                            ZStack{
                                Circle()
                                    .foregroundStyle(Color.accentColor)
                                Circle()
                                    .padding(3)
                                    .foregroundStyle(.background)
                                    .overlay {
                                        Image(systemName: "arrow.up.right")
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                    }
                                
                                
                            }
                            .frame(width: 45)
                            .hAllign(.trailing)
                        }
                    }
                    .frame(maxWidth: 150)
                }
                .frame(height: 45)
                .vAllign(.bottom)
            }
            .padding(30)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .containerRelativeFrame(.horizontal, count: sizeClass == .regular ? 2 : 1, spacing: 15)
        .scrollTransition(axis: .horizontal) { content, phase in
            content
                .scaleEffect(
                    x: phase.isIdentity ? 1 : 0.80,
                    y: phase.isIdentity ? 1 : 0.80
                )
        }
    }
}

#Preview {
    ContentView()
}
