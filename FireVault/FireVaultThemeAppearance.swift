//
//  FireVaultThemeAppearance.swift
//  FireVault
//
//  Shared UIKit appearance for navigation and controls. List and Form rows
//  remain under SwiftUI's control so native grouped geometry is preserved.
//

import SwiftUI
import UIKit

enum FireVaultThemeAppearance {
    static func configure() {
        let canvas = NativeShellPalette.backgroundUIColor
        let surface = NativeShellPalette.surfaceUIColor
        let raised = NativeShellPalette.navigationBackgroundUIColor
        let text = NativeShellPalette.primaryTextUIColor
        let border = NativeShellPalette.borderUIColor

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = canvas
        navigation.shadowColor = border
        navigation.titleTextAttributes = [.foregroundColor: text]
        navigation.largeTitleTextAttributes = [.foregroundColor: text]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = raised
        tabBar.shadowColor = border
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        UISegmentedControl.appearance().selectedSegmentTintColor = surface
        UISwitch.appearance().onTintColor = UIColor(
            red: 0.075,
            green: 0.278,
            blue: 0.420,
            alpha: 1
        )
    }
}

extension View {
    func fireVaultThemedCollection() -> some View {
        scrollContentBackground(.hidden)
            .background(NativeShellPalette.background)
            .listRowBackground(NativeShellPalette.surface)
            .listRowSeparatorTint(NativeShellPalette.hairline)
            .tint(NativeShellPalette.blue)
            .toolbarBackground(NativeShellPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
