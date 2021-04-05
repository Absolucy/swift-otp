//
//  OtpView.swift
//  PlaygroundOTP
//
//  Created by Aspen on 4/5/21.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
	import UIKit
#else
	import AppKit
#endif

public struct OtpView: View {
	private let timer = Timer.publish(every: 1, on: .main, in: .common)
	private var numberFormatter: NumberFormatter = {
		var formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = " "
		return formatter
	}()

	private var cutoff: CGFloat
	@State private var otp: OtpInfo
	@State private var code: UInt64?
	@State private var progress: Double = 1.0
	@State private var progressSize: Double = 0.875
	@State private var refreshIn: Int
	@State private var offset: CGFloat = 0.0
	@Binding private var deleting: OtpInfo?
	@Binding private var toast: Bool

	#if canImport(UIKit)
		private let backgroundColor = Color(UIColor.systemFill)
		private let textColor = Color(UIColor.label)
	#else
		private let backgroundColor = Color(NSColor.controlColor)
		private let textColor = Color(NSColor.textColor)
	#endif

	public init(otp: OtpInfo, cutoff: CGFloat, deleting: Binding<OtpInfo?>, toast: Binding<Bool>) {
		self._otp = State(wrappedValue: otp)
		self._refreshIn = State(wrappedValue: otp.entry.get_display_value())
		self._deleting = deleting
		self._toast = toast
		self.cutoff = cutoff

		let subscription = self.timer.connect()
		switch self.otp.entry {
		case let .hotp(_, digits, _):
			self.numberFormatter.minimumIntegerDigits = digits
			subscription.cancel()
		case let .totp(_, digits, _):
			self.numberFormatter.minimumIntegerDigits = digits
		}
	}

	public var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 32)
				.foregroundColor(backgroundColor)
			HStack {
				CircularProgress(
					progress: $progress,
					display: $refreshIn,
					multiplier: $progressSize
				)
				.padding(.trailing, 15)
				.onReceive(self.timer) { _ in
					if case let .totp(_, _, interval) = self.otp.entry {
						let time = Date().timeIntervalSince1970
						if time.remainder(dividingBy: interval) == 0 {
							withAnimation(.linear(duration: 1)) {
								self.progress = 1.0
							}
						} else {
							// Calculate when the NEXT interval will start
							let nextUpdate = Double(ceil(time / interval) * interval)
							withAnimation(.linear(duration: 1)) {
								self.progress = 1.0 - ((nextUpdate - time) / interval)
							}
						}
					}
				}
				.onLongPressGesture {
					withAnimation(.easeOut(duration: 1)) {
						self.deleting = self.otp
					}
				}

				VStack {
					if let code = self.code {
						Text(self.numberFormatter.string(from: NSNumber(value: code))!)
							.font(.system(.title, design: .monospaced))
							.padding(.bottom, 5.0)

					} else {
						Text("--- ---")
							.font(.system(.title, design: .monospaced))
							.padding(.bottom, 5.0)
					}
					if let issuer = self.otp.issuer {
						Text(issuer)
							.font(.callout)
							.fontWeight(.light)
							.opacity(0.45)
					}
					if let name = self.otp.name {
						Text(name)
							.font(.callout)
							.fontWeight(.light)
							.opacity(0.45)
					}
				}
				.foregroundColor(textColor)
				.multilineTextAlignment(.center)
			}
			.onReceive(self.timer) { _ in
				if case .totp = self.otp.entry {
					self.code = self.otp.entry.code()
					self.refreshIn = self.otp.entry.get_display_value()
				}
			}
			.padding()
		}
		.frame(minWidth: 250, maxWidth: 325)
		.modifier(
			NeonEffect(
				base: RoundedRectangle(cornerRadius: 32),
				color: deleting?.id == otp.id ? Color.red : Color.purple,
				brightness: 0.1,
				innerSize: 1.5,
				middleSize: 3,
				outerSize: 5,
				blur: 5
			)
		)
		.offset(x: self.offset)
		.gesture(
			DragGesture(minimumDistance: 25, coordinateSpace: .global)
				.onChanged { swipe in
					self.offset = swipe.translation.width
				}
				.onEnded { swipe in
					withAnimation(Animation.spring()) {
						self.offset = 0
					}
					if swipe.location.x < (self.cutoff * 0.15) || swipe.location.x > (self.cutoff * 0.85) {
						self.deleting = self.otp
					}
				}
		)
		.highPriorityGesture(TapGesture().onEnded {
			withAnimation(Animation.linear(duration: 0.25)) {
				self.progressSize = 1
				self.toast = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					withAnimation(Animation.linear(duration: 0.5)) {
						self.progressSize = 0.875
					}
				}
				DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
					withAnimation(Animation.linear(duration: 0.5)) {
						self.toast = false
					}
				}
			}
			let code = self.otp.entry.code()
			self.code = code
			self.refreshIn = self.otp.entry.get_display_value()
			#if os(macOS)
				NSPasteboard.general.declareTypes([.string], owner: nil)
				NSPasteboard.general.setString(String(format: "%u", code), forType: .string)
			#else
				UIPasteboard.general.string = String(format: "%u", code)
			#endif
		})
	}
}
