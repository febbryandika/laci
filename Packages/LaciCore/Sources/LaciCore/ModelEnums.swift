import Foundation

/// The raw strings SPEC §4 stores, typed at the persistence boundary and nowhere else.
public enum PaymentMethod: String, Hashable, Sendable, CaseIterable {
    case cash, qris, transfer
}

public enum MovementReason: String, Hashable, Sendable, CaseIterable {
    case sale, void, stockIn = "stock_in", stocktake, waste
}

/// Raw values match `AVMetadataObject.ObjectType`, so the scanner stores exactly what it read.
public enum Symbology: String, Hashable, Sendable, CaseIterable {
    case ean13 = "org.gs1.EAN-13"
    case ean8 = "org.gs1.EAN-8"
    case code128 = "org.iso.Code128"
}

public extension SchemaV1.Sale {
    var paymentMethod: PaymentMethod? {
        PaymentMethod(rawValue: paymentMethodRaw)
    }
}

public extension SchemaV1.StockMovement {
    var reason: MovementReason? {
        MovementReason(rawValue: reasonRaw)
    }
}

public extension SchemaV1.Barcode {
    /// The SPEC names the stored string `symbology`, so the typed view needs another name.
    var symbologyKind: Symbology? {
        Symbology(rawValue: symbology)
    }
}
