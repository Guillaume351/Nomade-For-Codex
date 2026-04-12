//
//  NomadeLiveActivityExtensionLiveActivity.swift
//  NomadeLiveActivityExtension
//
//  Created by Guillaume Claverie on 12/04/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NomadeLiveActivityExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct NomadeLiveActivityExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NomadeLiveActivityExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension NomadeLiveActivityExtensionAttributes {
    fileprivate static var preview: NomadeLiveActivityExtensionAttributes {
        NomadeLiveActivityExtensionAttributes(name: "World")
    }
}

extension NomadeLiveActivityExtensionAttributes.ContentState {
    fileprivate static var smiley: NomadeLiveActivityExtensionAttributes.ContentState {
        NomadeLiveActivityExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: NomadeLiveActivityExtensionAttributes.ContentState {
         NomadeLiveActivityExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: NomadeLiveActivityExtensionAttributes.preview) {
   NomadeLiveActivityExtensionLiveActivity()
} contentStates: {
    NomadeLiveActivityExtensionAttributes.ContentState.smiley
    NomadeLiveActivityExtensionAttributes.ContentState.starEyes
}
