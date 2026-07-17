//
//  LaboratorySettingView.swift
//  LabSettingView
//

import SwiftUI

struct LaboratorySettingView: View {
    @Binding private var bypassesSNIFiltering: Bool

    init(bypassesSNIFiltering: Binding<Bool>) {
        _bypassesSNIFiltering = bypassesSNIFiltering
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    L10n.Localizable.LaboratorySettingView.Title.bypassesSNIFiltering,
                    isOn: $bypassesSNIFiltering
                )
            }
        }
        .navigationTitle(L10n.Localizable.LaboratorySettingView.Title.laboratory)
    }
}

struct LaboratorySettingView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LaboratorySettingView(
                bypassesSNIFiltering: .constant(false)
            )
        }
    }
}
