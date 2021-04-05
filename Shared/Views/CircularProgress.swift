//
//  CircularProgress.swift
//  PlaygroundOTP
//
//  Created by Aspen on 4/5/21.
//

import Foundation
import SwiftUI

public struct CircularProgress: View {
	@Binding public var progress: Double
	@Binding public var display: Int
	@Binding public var multiplier: Double

	public var body: some View {
		Circle()
			.fill(LinearGradient(
				gradient: Gradient(colors: [Color.purple, Color.pink]),
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			))
			.frame(width: 96, height: 96)
			.overlay(
				Circle()
					.trim(from: 0, to: CGFloat(self.progress))
					.stroke(style: StrokeStyle(lineWidth: 5.0, lineCap: .round, lineJoin: .round))
					.frame(width: CGFloat(96 * multiplier), height: CGFloat(96 * multiplier))
					.foregroundColor(self.multiplier > 0.875 ? Color.green : Color.purple)
					.brightness(0.25)
					.blur(radius: 0.75)
					.overlay(
						Text("\(display)")
							.foregroundColor(.white)
							.font(.system(.title, design: .monospaced))
					)
					.allowsHitTesting(false)
			)
	}
}
