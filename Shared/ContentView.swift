//
//  ContentView.swift
//  Shared
//
//  Created by Aspen on 4/3/21.
//

import Combine
import CryptoKit
import SwiftUI
#if canImport(UIKit)
	import UIKit
#else
	import AppKit
#endif

// This is just an implementation of RFC 4226.
// A simpler explaination is available on Wikipedia: https://en.wikipedia.org/wiki/HMAC-based_One-Time_Password
public func hotp_code(key: Data, digits: Double = 6, counter: UInt64) -> UInt64 {
	// First, we counter our 64-bit counter into 8 big-endian bytes.
	let counter_bytes = withUnsafeBytes(of: counter.bigEndian, Array.init)
	assert(counter_bytes.count == 8)
	// Technically HOTP and TOTP support more than SHA-1, but 99.9% of all codes are SHA-1.
	// Anyways, we hash the big-endian counter using our key as well, the key.
	let digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counter_bytes, using: SymmetricKey(data: key)))
	// Now, get the last byte of the HMAC digest, and modulo it by 16, to get our starting index, aka "i"
	let i = digest.last! % 16
	// Truncate our digest, getting the 4 bytes starting at i.
	let truncated = digest[i ..< i + 4]
	var code: UInt32 = 0
	// Convert the truncated bytes into a unsigned 32-bit int, then modulo it by 2^31
	// We have to copy the bytes, else we risk a crash from unaligned memory.
	// Swift plz add from_be/le/ne_bytes like Rust has.
	// Source: https://stackoverflow.com/a/38024025
	assert(withUnsafeMutableBytes(of: &code) { truncated.copyBytes(to: $0) } == MemoryLayout.size(ofValue: code))
	// And to finish this up, we modulo the code by 2^31, then 10^digits.
	return UInt64(code % UInt32(pow(2.0, 31))) % UInt64(pow(10, Double(digits)))
}

public struct OtpInfo: Identifiable, Hashable {
	public static func == (lhs: OtpInfo, rhs: OtpInfo) -> Bool {
		lhs.id == rhs.id || (lhs.issuer == rhs.issuer && lhs.name == rhs.name && lhs.entry == rhs.entry)
	}

	public let id = UUID()
	public var issuer: String?
	public var name: String?
	public var entry: OtpEntry

	public init(issuer: String? = nil, name: String? = nil, entry: OtpEntry) {
		self.issuer = issuer
		self.name = name
		self.entry = entry
	}
}

public struct NeonEffect<S: Shape>: ViewModifier {
	public var base: S
	public var color: Color
	public var brightness: Double
	public var inner: Double
	public var mid: Double?
	public var outer: Double?
	public var inner_blur: Double?
	public var blur: Double

	public func body(content: Content) -> some View {
		content
			.overlay(
				self.base
					.stroke(self.color, lineWidth: CGFloat(self.inner))
					.brightness(self.brightness)
					.blur(radius: CGFloat(self.inner_blur ?? self.blur))
					.allowsHitTesting(false)
			)
			.overlay(
				self.base
					.stroke(self.color, lineWidth: CGFloat(self.mid ?? self.inner))
					.brightness(self.brightness)
					.allowsHitTesting(false)
			)
			.background(
				self.base
					.stroke(self.color, lineWidth: CGFloat(self.outer ?? (self.mid ?? self.inner)))
					.brightness(self.brightness)
					.blur(radius: CGFloat(self.blur))
					.allowsHitTesting(false)
			)
			.background(
				self.base
					.stroke(self.color, lineWidth: CGFloat(self.outer ?? (self.mid ?? self.inner)))
					.brightness(self.brightness)
					.blur(radius: CGFloat(self.blur))
					.opacity(0.2)
					.allowsHitTesting(false)
			)
	}
}

public enum OtpEntry: Hashable {
	public static func == (lhs: OtpEntry, rhs: OtpEntry) -> Bool {
		switch (lhs, rhs) {
		case let (.hotp(lkey, ldigits, lcounter), .hotp(rkey, rdigits, rcounter)):
			return lkey == rkey && ldigits == rdigits && lcounter == rcounter
		case let (.totp(lkey, ldigits, linterval), .totp(rkey, rdigits, rinterval)):
			return lkey == rkey && ldigits == rdigits && linterval == rinterval
		default:
			return false
		}
	}

	case hotp(key: Data, digits: Int, counter: UInt64)
	case totp(key: Data, digits: Int, interval: Double)

	public mutating func code() -> UInt64 {
		switch self {
		case let .hotp(key, digits, counter):
			let code = hotp_code(key: key, digits: Double(digits), counter: counter)
			self = .hotp(key: key, digits: digits, counter: counter + 1)
			return code
		case let .totp(key, digits, interval):
			let counter = UInt64(Date().timeIntervalSince1970 / interval)
			return hotp_code(key: key, digits: Double(digits), counter: counter)
		}
	}

	public func get_display_value() -> Int {
		switch self {
		case let .hotp(_, _, counter):
			return Int(counter)
		case let .totp(_, _, interval):
			let time = Date().timeIntervalSince1970
			let next_update = Double(ceil(time / interval) * interval)
			return Int((next_update - time).rounded())
		}
	}
}

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

public struct OtpView: View {
	private let timer = Timer.publish(every: 1, on: .main, in: .common)
	private var num_formatter: NumberFormatter = {
		var formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = " "
		return formatter
	}()

	private var cutoff: CGFloat
	@State private var otp: OtpInfo
	@State private var code: UInt64?
	@State private var progress: Double = 1.0
	@State private var progress_size_mult: Double = 0.875
	@State private var refresh_in: Int
	@State private var offset: CGFloat = 0.0
	@Binding private var deleting: OtpInfo?
	@Binding private var toast: Bool

	#if canImport(UIKit)
		private let background_color = Color(UIColor.systemFill)
		private let text_color = Color(UIColor.label)
	#else
		private let background_color = Color(NSColor.controlColor)
		private let text_color = Color(NSColor.textColor)
	#endif

	public init(otp: OtpInfo, cutoff: CGFloat, deleting: Binding<OtpInfo?>, toast: Binding<Bool>) {
		self._otp = State(wrappedValue: otp)
		self._refresh_in = State(wrappedValue: otp.entry.get_display_value())
		self._deleting = deleting
		self._toast = toast
		self.cutoff = cutoff

		let subscription = self.timer.connect()
		switch self.otp.entry {
		case let .hotp(_, digits, _):
			self.num_formatter.minimumIntegerDigits = digits
			subscription.cancel()
		case let .totp(_, digits, _):
			self.num_formatter.minimumIntegerDigits = digits
		}
	}

	public var body: some View {
		ZStack {
			RoundedRectangle(cornerRadius: 32)
				.foregroundColor(background_color)
			HStack {
				CircularProgress(
					progress: $progress,
					display: $refresh_in,
					multiplier: $progress_size_mult
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
							let next_update = Double(ceil(time / interval) * interval)
							withAnimation(.linear(duration: 1)) {
								self.progress = 1.0 - ((next_update - time) / interval)
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
						Text(self.num_formatter.string(from: NSNumber(value: code))!)
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
				.foregroundColor(text_color)
				.multilineTextAlignment(.center)
			}
			.onReceive(self.timer) { _ in
				if case .totp = self.otp.entry {
					self.code = self.otp.entry.code()
					self.refresh_in = self.otp.entry.get_display_value()
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
				inner: 1.5,
				mid: 3,
				outer: 5,
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
				self.progress_size_mult = 1
				self.toast = true
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					withAnimation(Animation.linear(duration: 0.5)) {
						self.progress_size_mult = 0.875
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
			self.refresh_in = self.otp.entry.get_display_value()
			#if os(macOS)
				NSPasteboard.general.declareTypes([.string], owner: nil)
				NSPasteboard.general.setString(String(format: "%u", code), forType: .string)
			#else
				UIPasteboard.general.string = String(format: "%u", code)
			#endif
		})
	}
}

public struct AddOtpView: View {
	@Binding public var accounts: [OtpInfo]
	@Binding public var adding_account: Bool
	@State private var issuer: String = ""
	@State private var name: String = ""
	@State private var key: String = ""
	@State private var digits = 6
	@State private var interval = 30
	@State private var counter = 0
	@State private var is_hotp = false
	@State private var num_formatter: NumberFormatter = {
		var formatter = NumberFormatter()
		formatter.numberStyle = .decimal
		formatter.groupingSeparator = " "
		return formatter
	}()

	#if canImport(UIKit)
		private let background_color = Color(UIColor.systemFill)
		private let text_color = Color(UIColor.label)
		private let disabled_color = Color(UIColor.placeholderText)
	#else
		private let background_color = Color(NSColor.controlColor)
		private let text_color = Color(NSColor.textColor)
		private let disabled_color = Color(NSColor.disabledControlTextColor)
	#endif

	public var body: some View {
		VStack {
			ZStack {
				VStack {
					Picker(selection: $is_hotp, label: EmptyView()) {
						Text("TOTP").tag(false)
						Text("HOTP").tag(true)
					}.pickerStyle(SegmentedPickerStyle())
					SecureField("OTP Key", text: $key)
						.textFieldStyle(RoundedBorderTextFieldStyle())
					if self.is_hotp {
						Stepper(onIncrement: {
						        	counter += 1
						        },
						        onDecrement: {
						        	counter = max(counter - 1, 0)
						        }) {
							Text("Counter: \(counter)")
						}
					} else {
						Stepper(onIncrement: {
						        	interval += 1
						        },
						        onDecrement: {
						        	interval = max(interval - 1, 1)
						        }) {
							Text("\(interval) seconds")
						}
					}
					Stepper(onIncrement: {
					        	digits = min(digits + 1, 10)
					        	num_formatter.minimumIntegerDigits = digits
					        },
					        onDecrement: {
					        	digits = max(digits - 1, 6)
					        	num_formatter.minimumIntegerDigits = digits
					        }) { () -> AnyView in
						num_formatter.minimumIntegerDigits = digits
						return AnyView(Text(num_formatter.string(from: 0) ?? "\(digits) digits"))
					}
				}
				.padding(10)
			}
			.modifier(
				NeonEffect(
					base: RoundedRectangle(cornerRadius: 5),
					color: Color.yellow,
					brightness: 0.025,
					inner: 2,
					mid: 3,
					outer: 5,
					inner_blur: 0,
					blur: 5
				)
			)
			Divider().padding(.vertical, 5)
			ZStack {
				VStack {
					TextField("Issuer", text: $issuer)
						.textFieldStyle(RoundedBorderTextFieldStyle())
					TextField("Account Name", text: $name)
						.textFieldStyle(RoundedBorderTextFieldStyle())
				}.padding(10)
			}.modifier(
				NeonEffect(
					base: RoundedRectangle(cornerRadius: 5),
					color: Color.pink,
					brightness: 0.025,
					inner: 2,
					mid: 3,
					outer: 5,
					inner_blur: 0,
					blur: 5
				)
			)
			Divider().padding(.vertical, 5)
			HStack {
				Button(action: {
					let issuer = self.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
					let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
					var entry: OtpEntry
					if self.is_hotp {
						entry = .hotp(key: self.key.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!,
						              digits: self.digits, counter: UInt64(self.counter))
					} else {
						entry = .totp(key: self.key.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!,
						              digits: self.digits, interval: Double(self.interval))
					}
					withAnimation(Animation.easeInOut(duration: 1)) {
						self.accounts.append(OtpInfo(
							issuer: issuer.isEmpty ? nil : issuer,
							name: name.isEmpty ? nil : name,
							entry: entry
						))
					}
					self.adding_account = false
				}) {
					Text("Add")
						.foregroundColor(text_color)
						.opacity(key.isEmpty || interval < 1 || digits < 6 || digits > 10 ? 0.25 : 1.0)
						.padding()
				}
				.buttonStyle(BorderlessButtonStyle())
				.frame(minWidth: 0, maxWidth: .infinity)
				.background(background_color.overlay(Color.green.opacity(0.75)).blendMode(.hardLight))
				.disabled(key.isEmpty || interval < 1 || digits < 6 || digits > 10)
				.cornerRadius(15)
				.modifier(NeonEffect(
					base: RoundedRectangle(cornerRadius: 15),
					color: .green,
					brightness: 0.1,
					inner: 1,
					mid: 2,
					outer: 4,
					blur: 5
				)).padding(.horizontal, 5)

				Button(action: {
					self.adding_account = false
				}) {
					Text("Discard")
						.foregroundColor(text_color)
						.padding()
				}
				.buttonStyle(BorderlessButtonStyle())
				.frame(minWidth: 0, maxWidth: .infinity)
				.background(background_color.overlay(Color.red.opacity(0.75)).blendMode(.hardLight))
				.cornerRadius(15)
				.modifier(NeonEffect(base: RoundedRectangle(cornerRadius: 15), color: .red, brightness: 0.1, inner: 1, mid: 2,
				                     outer: 4, blur: 5)).padding(.horizontal, 5)
			}
		}.padding()
	}
}

public struct ContentView: View {
	@Environment(\.colorScheme) var color_scheme
	@State var accounts: [OtpInfo] = [
		OtpInfo(
			issuer: "Example Issuer",
			name: "totp@example.com",
			entry: .totp(key: "example key".data(using: .utf8)!, digits: 6, interval: 30.0)
		),
		OtpInfo(
			issuer: "Example Issuer",
			name: "hotp@example.com",
			entry: .hotp(key: "example key".data(using: .utf8)!, digits: 6, counter: 1)
		),
	]
	@State var adding_account = false
	@State var deleting: OtpInfo?
	@State var copied_toast = false
	@State var search = ""

	#if canImport(UIKit)
		let toast_color = Color(UIColor.systemFill)
		let field_color = Color(UIColor.tertiarySystemFill)
		let add_btn_color = Color(UIColor.secondarySystemBackground)
	#else
		let toast_color = Color(NSColor.selectedControlColor)
		let field_color = Color(NSColor.textBackgroundColor)
		let add_btn_color = Color(NSColor.controlBackgroundColor)
	#endif

	public init() {}

	public var body: some View {
		VStack {
			GeometryReader { geometry in
				ZStack {
					VStack {
						HStack(alignment: .center) {
							Image(systemName: "plus.circle.fill")
								.renderingMode(.template)
								.foregroundColor(add_btn_color)
								.font(.system(size: 24))
								.background(
									Circle()
										.foregroundColor(add_btn_color)
										.colorInvert()
										.allowsHitTesting(false)
								)
								.modifier(
									NeonEffect(base: Circle(), color: Color.green, brightness: 0.025, inner: 1.5, mid: 3, outer: 5, blur: 3)
								)
								.onTapGesture {
									self.adding_account = true
								}

							TextField("Search", text: $search)
								.textFieldStyle(RoundedBorderTextFieldStyle())
								.onChange(of: search, perform: { [search] new_search in
									let new_search = new_search.trimmingCharacters(in: .whitespacesAndNewlines)
									if self.accounts
										.firstIndex(where: { $0.name?.localizedCaseInsensitiveContains(new_search) ?? false || $0.issuer?
												.localizedCaseInsensitiveContains(new_search) ?? false
										}) == nil, new_search.count > search.count
									{
										self.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
									}
								})
								.modifier(
									NeonEffect(
										base: RoundedRectangle(cornerRadius: 5.0),
										color: Color.blue,
										brightness: 0.025,
										inner: 0.5,
										mid: 3,
										outer: 5,
										blur: 3
									)
								)
								.padding(.leading, 10)

						}.padding(.bottom, 5)
						ScrollView {
							let search_field = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
							LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 325))], alignment: .center, spacing: 7.5) {
								ForEach(search_field.isEmpty ? self.accounts : self.accounts
									.filter {
										$0.name?.localizedCaseInsensitiveContains(search_field) ?? false || $0.issuer?
											.localizedCaseInsensitiveContains(search_field) ?? false
									}) { account in
									OtpView(otp: account, cutoff: geometry.size.width, deleting: $deleting, toast: $copied_toast)
										.padding()
										.transition(
											AnyTransition.asymmetric(
												insertion: AnyTransition.move(edge: .leading),
												removal: AnyTransition.move(edge: .trailing)
											).combined(with: AnyTransition.opacity)
										)
								}
							}
							.padding()
							.frame(minWidth: geometry.size.width, maxWidth: geometry.size.width)
						}
						VStack(alignment: .center) {
							Text("Click or tap any account to copy the current code to your clipboard.")
								.font(.caption)
								.fontWeight(.light)
								.opacity(0.75)
							Text("Long-click/press on an account's ball to delete the account.")
								.font(.caption)
								.fontWeight(.light)
								.opacity(0.75)
						}
						.multilineTextAlignment(.center)
					}
					HStack {
						Spacer()
						VStack {
							Spacer()
							ZStack {
								RoundedRectangle(cornerRadius: 32)
									.foregroundColor(toast_color)
								Text("Code copied to clipboard")
									.padding()
							}
							.fixedSize()
						}.padding()
						Spacer()
					}
					.opacity(self.copied_toast ? 0.9 : 0.0)
					.allowsHitTesting(false)
				}
			}
		}
		.padding()
		.alert(item: $deleting.animation(.easeInOut(duration: 1))) { item in
			var alert_text: String
			switch (item.issuer, item.name) {
			case let (.some(issuer), .some(name)):
				alert_text = "the account \"\(name)\" for \"\(issuer)\""
			case let (.none, .some(name)):
				alert_text = "the account \"\(name)\""
			case let (.some(issuer), .none):
				alert_text = "the account for \"\(issuer)\""
			case (.none, .none):
				alert_text = "this account"
			}
			return Alert(
				title: Text("Confirm Delete"),
				message: Text("Are you sure that you want to PERMANENTLY DELETE \(alert_text)"),
				primaryButton: .destructive(Text("Delete").bold()) {
					withAnimation(Animation.easeInOut(duration: 1)) {
						self.accounts.removeAll(where: { $0.id == item.id })
					}
				},
				secondaryButton: .cancel()
			)
		}
		.sheet(isPresented: $adding_account) {
			AddOtpView(accounts: $accounts, adding_account: $adding_account)
				.preferredColorScheme(self.color_scheme)
		}
	}
}

struct ContentView_Preview_Light: PreviewProvider {
	static var previews: some View {
		ContentView()
			.preferredColorScheme(.light)
	}
}

struct ContentView_Preview_Dark: PreviewProvider {
	static var previews: some View {
		ContentView()
			.preferredColorScheme(.dark)
	}
}
