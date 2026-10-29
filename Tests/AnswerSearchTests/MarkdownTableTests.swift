import Testing
@testable import AnswerSearchKit

@Suite struct MarkdownTableTests {
    private func rowCount(_ markdown: String) -> Int {
        markdown.components(separatedBy: "\n").filter { $0.hasPrefix("|") }.count
    }

    @Test func supportsOptionalOuterPipesAndEscapedPipes() {
        let answer = [
            "Factor | Induction | Gas",
            "--- | --- | ---",
            "Speed | Faster | Slower",
            #"Controls | Touch \| knobs | Knobs"#,
        ].joined(separator: "\n")
        let normalized = MarkdownTables.normalize(answer)
        for want in ["| Factor | Induction | Gas |", "| Speed | Faster | Slower |", #"| Controls | Touch \| knobs | Knobs |"#] {
            #expect(normalized.contains(want), "missing \(want) in:\n\(normalized)")
        }
    }

    @Test func fitsExtraCellsWithoutBreakingFollowingRows() {
        let answer = [
            "| Factor | Induction | Gas |",
            "|---|---|---|",
            "| Controls | Touch | with slider | Knobs |",
            "| Safety | Cooler surface | Open flame |",
        ].joined(separator: "\n")
        let normalized = MarkdownTables.normalize(answer)
        #expect(normalized.contains(#"| Controls | Touch | with slider \| Knobs |"#))
        #expect(rowCount(normalized) == 4) // header, separator, two rows
    }

    @Test func repairsMixedCompleteAndSplitRows() {
        let answer = [
            "| Factor | Induction | Gas |",
            "|---|---|---|",
            "| Speed | Faster | Slower |",
            "| Energy efficiency | Up to 3x more efficient | Less efficient |",
            "| Precision | Greater control with rapid adjustments | | Good, but |",
            "",
            "gas can't reach very low temperatures without extinguishing",
            "",
            "|",
            "| Safety |",
            "",
            "Cool surface, no open flame — safer overall",
            "",
            "|",
            "",
            "Combustion emissions require ventilation; open flame raises burn risk",
            "",
            "|",
            "| Cleanup | Smooth glass surface | Grates and burners |",
        ].joined(separator: "\n")
        let normalized = MarkdownTables.normalize(answer)
        #expect(rowCount(normalized) == 7) // header, separator, five rows
        for want in [
            "| Precision | Greater control with rapid adjustments | Good, but gas can't reach very low temperatures without extinguishing |",
            "| Safety | Cool surface, no open flame — safer overall | Combustion emissions require ventilation; open flame raises burn risk |",
            "| Cleanup | Smooth glass surface | Grates and burners |",
        ] {
            #expect(normalized.contains(want), "missing \(want) in:\n\(normalized)")
        }
    }

    @Test func joinsMultilineCellsEndingWithPipe() {
        let answer = [
            "| Criteria | Gas | Induction |",
            "|---|---|---|",
            "| Speed & Heat-Up | Slower; heats cookware indirectly | Faster; heats cookware directly |",
            "| Temperature Control | Harder; gas ranges tend to run hot | More precise than any domestic gas burner at",
            "",
            "medium-low to high settings; digital control from gentle simmer to full boil |",
            "| Energy Efficiency |",
            "",
            "Gas ranges convert only about 32% of their energy into cooking heat",
            "",
            "|",
            "",
            "Achieves up to 85% efficiency via direct electromagnetic heat transfer",
            "",
            "|",
            "| Safety & Cleanliness | Open flame; grates trap grease; combustion gases released indoors |",
            "",
            "Safer",
            "",
            "— surface stays cool, no open flame, and spills don't burn on |",
        ].joined(separator: "\n")
        let normalized = MarkdownTables.normalize(answer)
        #expect(rowCount(normalized) == 6) // header, separator, four rows
        for want in [
            "More precise than any domestic gas burner at medium-low to high settings; digital control from gentle simmer to full boil",
            "| Energy Efficiency | Gas ranges convert only about 32% of their energy into cooking heat | Achieves up to 85% efficiency via direct electromagnetic heat transfer |",
            "| Safety & Cleanliness | Open flame; grates trap grease; combustion gases released indoors | Safer — surface stays cool, no open flame, and spills don't burn on |",
        ] {
            #expect(normalized.contains(want), "missing \(want) in:\n\(normalized)")
        }
    }

    @Test func keepsUnterminatedCellInItsColumn() {
        let answer = [
            "| Criteria | Gas | Induction |",
            "|---|---|---|",
            "| **Energy Efficiency** |",
            "~40–55% of energy converted to heat",
            "|",
            "~85–90% of energy converted to heat",
            "|",
            "| **Safety** | Open flame; hot grates;",
            "",
            "burning methane can release pollutants linked to asthma",
            "",
            "|",
            "",
            "Heats cookware directly; the surface stays relatively cool",
            "",
            "|",
            "| **Upfront & Running Cost** |",
            "Gas cooktops are cheaper to buy upfront",
            "|",
            "More efficient over the product lifecycle",
            "|",
            "| **Cookware & Versatility** | Works with any cookware |",
            "Some high-heat techniques are better suited to gas",
            "; requires magnetic-base cookware |",
            "",
            "**Bottom line:** Induction wins on efficiency and safety.",
        ].joined(separator: "\n")
        let normalized = MarkdownTables.normalize(answer)
        #expect(rowCount(normalized) == 6) // header, separator, four rows
        for want in [
            "| **Safety** | Open flame; hot grates; burning methane can release pollutants linked to asthma | Heats cookware directly; the surface stays relatively cool |",
            "| **Upfront & Running Cost** | Gas cooktops are cheaper to buy upfront | More efficient over the product lifecycle |",
            "| **Cookware & Versatility** | Works with any cookware | Some high-heat techniques are better suited to gas ; requires magnetic-base cookware |",
            "**Bottom line:** Induction wins on efficiency and safety.",
        ] {
            #expect(normalized.contains(want), "missing \(want) in:\n\(normalized)")
        }
    }

    @Test func preservesCodeFences() {
        let answer = ["```", "| not | a | table |", "", "| keep | blank | line |", "```"].joined(separator: "\n")
        #expect(MarkdownTables.normalize(answer) == answer)
    }
}
