import Network

extension NWParameters {
    static var airProTransport: NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.noDelay = true

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.includePeerToPeer = true
        return parameters
    }

    static var airProDiscovery: NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }
}
