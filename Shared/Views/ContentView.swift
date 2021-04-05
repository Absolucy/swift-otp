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

public struct ContentView: View {
	@Environment(\.colorScheme) var colorScheme
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
		)
	]
	@State var addingAccount = false
	@State var deletingAccount: OtpInfo?
	@State var showCopiedToast = false
	@State var search = ""

	#if canImport(UIKit)
		let toastColor = Color(UIColor.systemFill)
		let fieldColor = Color(UIColor.tertiarySystemFill)
		let addButtonColor = Color(UIColor.secondarySystemBackground)
	#else
		let toastColor = Color(NSColor.selectedControlColor)
		let fieldColor = Color(NSColor.textBackgroundColor)
		let addButtonColor = Color(NSColor.controlBackgroundColor)
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
								.foregroundColor(addButtonColor)
								.font(.system(size: 24))
								.background(
									Circle()
										.foregroundColor(addButtonColor)
										.colorInvert()
										.allowsHitTesting(false)
								)
								.modifier(
									NeonEffect(
										base: Circle(),
										color: Color.green,
										brightness: 0.025,
										innerSize: 1.5,
										middleSize: 3,
										outerSize: 5,
										blur: 3
									)
								)
								.onTapGesture {
									self.addingAccount = true
								}

							TextField("Search", text: $search)
								.textFieldStyle(RoundedBorderTextFieldStyle())
								.onChange(of: search, perform: { [search] newSearch in
									let newSearch = newSearch.trimmingCharacters(in: .whitespacesAndNewlines)
									if
										self.accounts
										.contains(where: {
											$0.name?.localizedCaseInsensitiveContains(newSearch) ?? false || $0.issuer?
												.localizedCaseInsensitiveContains(newSearch) ?? false
										}), newSearch.count > search.count
									{
										self.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
									}
								})
								.modifier(
									NeonEffect(
										base: RoundedRectangle(cornerRadius: 5.0),
										color: Color.blue,
										brightness: 0.025,
										innerSize: 0.5,
										middleSize: 3,
										outerSize: 5,
										blur: 3
									)
								)
								.padding(.leading, 10)

						}.padding(.bottom, 5)
						ScrollView {
							let searchField = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
							LazyVGrid(
								columns: [GridItem(.adaptive(minimum: 250, maximum: 325))],
								alignment: .center,
								spacing: 7.5
							) {
								ForEach(
									searchField.isEmpty ? self.accounts : self.accounts
										.filter {
											$0.name?.localizedCaseInsensitiveContains(searchField) ?? false || $0
												.issuer?
												.localizedCaseInsensitiveContains(searchField) ?? false
										}
								) { account in
									OtpView(
										otp: account,
										cutoff: geometry.size.width,
										deleting: $deletingAccount,
										toast: $showCopiedToast
									)
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
									.foregroundColor(toastColor)
								Text("Code copied to clipboard")
									.padding()
							}
							.fixedSize()
						}.padding()
						Spacer()
					}
					.opacity(self.showCopiedToast ? 0.9 : 0.0)
					.allowsHitTesting(false)
				}
			}
		}
		.padding()
		.alert(item: $deletingAccount.animation(.easeInOut(duration: 1))) { item in
			var alertText: String
			switch (item.issuer, item.name) {
			case let (.some(issuer), .some(name)):
				alertText = "the account \"\(name)\" for \"\(issuer)\""
			case let (.none, .some(name)):
				alertText = "the account \"\(name)\""
			case let (.some(issuer), .none):
				alertText = "the account for \"\(issuer)\""
			case (.none, .none):
				alertText = "this account"
			}
			return Alert(
				title: Text("Confirm Delete"),
				message: Text("Are you sure that you want to PERMANENTLY DELETE \(alertText)"),
				primaryButton: .destructive(Text("Delete").bold()) {
					withAnimation(Animation.easeInOut(duration: 1)) {
						self.accounts.removeAll(where: { $0.id == item.id })
					}
				},
				secondaryButton: .cancel()
			)
		}
		.sheet(isPresented: $addingAccount) {
			AddOtpView(accounts: $accounts, addingAccount: $addingAccount)
				.preferredColorScheme(self.colorScheme)
		}
	}
}

struct ContentViewPreviewLight: PreviewProvider {
	static var previews: some View {
		ContentView()
			.preferredColorScheme(.light)
	}
}

struct ContentViewPreviewDark: PreviewProvider {
	static var previews: some View {
		ContentView()
			.preferredColorScheme(.dark)
	}
}
