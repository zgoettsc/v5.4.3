//
//  ContactTIPsView.swift
//  TIPsApp
//
//  Created by Zack Goettsche on 4/8/25.
//

import SwiftUI

struct ClinicLocation: Identifiable {
    let id = UUID()
    let name: String
    let address: String
}

struct ContactTIPsView: View {
    let locations = [
        ClinicLocation(
            name: "Long Beach Clinic",
            address: "2704 E Willow Street, Signal Hill, CA, 90755"
        ),
        ClinicLocation(
            name: "Vista Clinic",
            address: "2067 W Vista Way, Vista, CA, 92083"
        )
    ]
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 32) {
                    // Modern Header
                    VStack(spacing: 12) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Contact TIPs")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Access clinic locations, contacts, and services")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Clinic Locations Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Clinic Locations")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            ForEach(locations) { location in
                                Button(action: {
                                    openMapsApp(for: location)
                                }) {
                                    HStack(spacing: 16) {
                                        // Location Icon
                                        Circle()
                                            .fill(Color.red.opacity(0.2))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Image(systemName: "mappin.and.ellipse")
                                                    .font(.headline)
                                                    .foregroundColor(.red)
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(location.name)
                                                .font(.headline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.primary)
                                                .multilineTextAlignment(.leading)
                                            
                                            Text(location.address)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.tertiarySystemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color(.separator), lineWidth: 0.5)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                    
                    // Contact Information Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Contact Information")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            // Phone
                            Link(destination: URL(string: "tel:5624909900")!) {
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "phone.fill")
                                                .font(.headline)
                                                .foregroundColor(.blue)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Phone")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text("(562) 490-9900")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(.separator), lineWidth: 0.5)
                                        )
                                )
                            }
                            
                            // Fax
                            Link(destination: URL(string: "tel:5622701763")!) {
                                HStack(spacing: 16) {
                                    Circle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Image(systemName: "printer.fill")
                                                .font(.headline)
                                                .foregroundColor(.gray)
                                        )
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Fax")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text("(562) 270-1763")
                                            .font(.subheadline)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.tertiarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color(.separator), lineWidth: 0.5)
                                        )
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                    
                    // Email Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Email")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            EmailRow(icon: "envelope.fill", email: "enrollment@foodallergyinstitute.com", color: .orange)
                            EmailRow(icon: "envelope.fill", email: "info@foodallergyinstitute.com", color: .green)
                            EmailRow(icon: "envelope.fill", email: "scheduling@foodallergyinstitute.com", color: .purple)
                            EmailRow(icon: "envelope.fill", email: "patientbilling@foodallergyinstitute.com", color: .red)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                    
                    // Online Services Section
                    VStack(spacing: 20) {
                        HStack {
                            Text("Online Services")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        VStack(spacing: 12) {
                            LinkRow(
                                title: "TIPs Connect",
                                subtitle: "Report reactions, access resources, message on-call team",
                                icon: "link.circle.fill",
                                color: .blue,
                                url: "https://tipconnect.socalfoodallergy.org/"
                            )
                            
                            LinkRow(
                                title: "QURE4U My Care Plan",
                                subtitle: "View appointments, get reminders, sign documents",
                                icon: "calendar.circle.fill",
                                color: .green,
                                url: "https://www.web.my-care-plan.com/login"
                            )
                            
                            LinkRow(
                                title: "Athena Portal",
                                subtitle: "View appointments, discharge instructions, receipts",
                                icon: "doc.circle.fill",
                                color: .purple,
                                url: "https://11920.portal.athenahealth.com/"
                            )
                            
                            LinkRow(
                                title: "Netsuite",
                                subtitle: "TIP fee payments, schedule payments, autopay",
                                icon: "dollarsign.circle.fill",
                                color: .orange,
                                url: "https://6340501.app.netsuite.com/app/login/secure/privatelogin.nl?c=6340501"
                            )
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                        )
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func openMapsApp(for location: ClinicLocation) {
        // Format the address for URL
        let addressForURL = location.address.replacingOccurrences(of: " ", with: "+")
        
        // Try to open Apple Maps with address search
        if let url = URL(string: "maps://?address=\(addressForURL)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
        
        // Fallback to Google Maps in browser if Apple Maps fails
        if let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(addressForURL)") {
            UIApplication.shared.open(url)
        }
    }
}

struct EmailRow: View {
    let icon: String
    let email: String
    let color: Color
    
    var body: some View {
        Link(destination: URL(string: "mailto:\(email)")!) {
            HStack(spacing: 16) {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.headline)
                            .foregroundColor(color)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(email)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
            )
        }
    }
}

struct LinkRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let url: String
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 16) {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.headline)
                            .foregroundColor(color)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
            )
        }
    }
}

struct ContactTIPsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ContactTIPsView()
        }
    }
}
