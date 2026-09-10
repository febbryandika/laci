import Foundation

/// The Settings test print (SPEC §16 step 6): fixed content with no clock, so the bytes are a golden
/// fixture. The ruler is exactly one paper width, which makes a wrong 58/80 mm setting visible on
/// paper, and the character line shows what transliteration does to a name typed on the iPad.
public enum DiagnosticReceipt {
    public static func render(paper: PaperWidth) -> Data {
        var builder = ESCPOSBuilder(codepage: .cp437, columns: paper.columns)
        builder.initialize()
        builder.align(.center)
        builder.bold(true)
        builder.doubleHeight(true)
        builder.line("LACI")
        builder.doubleHeight(false)
        builder.bold(false)
        builder.line("Tes cetak")
        builder.align(.left)
        builder.rule()
        builder.line(String((1 ... paper.columns).map { Character(String($0 % 10)) }))
        builder.row("Kiri", "Kanan")
        builder.bold(true)
        builder.row("Tebal", "Rp 12.345")
        builder.bold(false)
        builder.line("Karakter: ā × – “kutip” … OK")
        builder.rule()
        builder.cut(.partial)
        return builder.data
    }
}
