//
//  Extensions.swift
//  PoliVerse
//
//  Created by Samuele Segrini on 19/10/23.
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
