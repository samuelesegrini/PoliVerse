//
//  Extensions.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 21/10/23.
//

import SwiftUI

extension View {
    func hAllign(_ alignment: Alignment) -> some View {
        self.frame(maxWidth: .infinity, alignment: alignment)
    }
    func vAllign(_ alignment: Alignment) -> some View {
        self.frame(maxHeight: .infinity, alignment: alignment)
    }
}

extension Font {
    static let enormousTitle = Font.custom("", size: 240, relativeTo: .largeTitle)
}
