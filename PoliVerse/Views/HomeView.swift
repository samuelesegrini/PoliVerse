//
//  HomeView.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 19/10/23.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack{
            VStack{
                ScrollView {
                    header()
                    ScrollView(.horizontal) {
                        HStack{
                            //TODO: get the course from the server and iterate throught the course list
                            ForEach(0...10, id: \.self){ course in
                                courseCard(courseName: "ACSO", imageName: course)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                }
                .scrollIndicators(.hidden)
            }        
            .padding()
        }
    }
    @ViewBuilder
    func header() -> some View {
        HStack{
            VStack(alignment: .leading, spacing: 0){
                Text("Matr. 986617")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Hey, Samuele Segrini")
                    .font(.title2)
                    .bold()
                    .fontDesign(.rounded)
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
            
            VStack(alignment: .leading){
                Text(courseName)
                    .minimumScaleFactor(0.3)
                    .lineLimit(3, reservesSpace: true)
                    .font(.title3)
                    .bold()
                    .fontDesign(.serif)
                    .frame(width: 165, alignment: .leading)
                
                /// Subtitle
                Text("our mission")
                    .textCase(.uppercase)
                    .bold()
                    .padding(.vertical, 10)
                
                /// Description
                Text("Artificial Intelligence (Al) has emerged as a transformative force, revolutionizing various aspects of our lives. With its ability to learn, reason, and adapt, Al is reshaping industries, enabling ground breaking advancements, and offering new opportunities for innovation. In this article. we delve into thel")
                    .font(.caption)
                    .lineLimit(4, reservesSpace: true)
                    .overlay {
                        Rectangle()
                            .foregroundStyle(.linearGradient(colors: [Color(.systemBackground).opacity(0.8), Color(.systemBackground).opacity(0)], startPoint: .bottom, endPoint: .top))
                    }
                Spacer()
                /// Read More Button
                HStack{
                    Menu {
                        Button("Vedi Forum", action: {})
                        Button("Apri Orario", action: {})
                        Button {
                            
                        } label: {
                            Label("Preferito", systemImage: "star.fill")
                        }
                    } label: {
                        Circle()
                            .foregroundStyle(.gray.secondary)
                            .overlay {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.white)
                            }
                    }
                    /// Like Button
                    Button{} label: {
                        Circle()
                            .foregroundStyle(.background)
                            .overlay {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.primary)
                            }
                    }
                    Spacer(minLength: 25)
                    Button{} label: {
                        ViewThatFits(in: .horizontal) {
                            ZStack{
                                Capsule()
                                    .foregroundStyle(Color.accentColor)
                                HStack{
                                    Text("Apri Corso")
                                        .bold()
                                        .font(.subheadline)
                                        .padding(.horizontal)
                                        .foregroundStyle(.background)
                                    Spacer()
                                    Circle()
                                        .padding(5)
                                        .foregroundStyle(.background)
                                        .overlay {
                                            Image(systemName: "arrow.up.right")
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                        }
                                }
                                
                            }
                            .frame(width: 165)
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
                    .frame(maxWidth: 165)
                }
                .frame(height: 45)
                .padding(.top)
            }
            .padding(30)
            .overlay(alignment: .topTrailing) {
                Image("\(imageName)")
                    .resizable()
                    .mask{
                        VStack(alignment: .trailing, spacing: 3){
                            RoundedRectangle(cornerRadius: 55)
                                .frame(width: 120, height: 35)
                            RoundedRectangle(cornerRadius: 55)
                                .frame(width: 80, height: 35)
                            RoundedRectangle(cornerRadius: 55)
                                .frame(width: 40, height: 35)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 15)
                    .padding(.top, 30)
            }
        }
        .padding(.horizontal)
        .aspectRatio(16.0 / 9.0 , contentMode: .fit)
        .containerRelativeFrame(.horizontal, count: sizeClass == .regular ? 2 : 1, spacing: 10)
        .scrollTransition(axis: .horizontal) { content, phase in
            content
                .scaleEffect(
                    x: phase.isIdentity ? 1.0 : 0.70,
                    y: phase.isIdentity ? 1.0 : 0.70
                )
        }
    }
}

#Preview {
    HomeView()
}
