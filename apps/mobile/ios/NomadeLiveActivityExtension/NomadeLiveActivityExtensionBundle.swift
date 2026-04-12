//
//  NomadeLiveActivityExtensionBundle.swift
//  NomadeLiveActivityExtension
//
//  Created by Guillaume Claverie on 12/04/2026.
//

import WidgetKit
import SwiftUI

@main
struct NomadeLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        NomadeLiveActivityExtension()
        NomadeLiveActivityExtensionControl()
        NomadeLiveActivityExtensionLiveActivity()
    }
}
