import CryptoKit
import Foundation
import Network
import Security

extension NWParameters {
    static func airPro(sharedSecret: Data) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.noDelay = true

        let parameters = NWParameters(tls: tlsOptions(sharedSecret: sharedSecret), tcp: tcpOptions)
        parameters.includePeerToPeer = true
        return parameters
    }

    static var airProDiscovery: NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }

    private static func tlsOptions(sharedSecret: Data) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()
        let identity = Data("AirPro".utf8)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: identity, using: SymmetricKey(data: sharedSecret))
        let preSharedKey = Data(authenticationCode)

        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            preSharedKey.dispatchData as __DispatchData,
            identity.dispatchData as __DispatchData
        )
        if let cipherSuite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(tlsOptions.securityProtocolOptions, cipherSuite)
        }
        return tlsOptions
    }
}

private extension Data {
    var dispatchData: DispatchData {
        withUnsafeBytes { DispatchData(bytes: $0) }
    }
}
