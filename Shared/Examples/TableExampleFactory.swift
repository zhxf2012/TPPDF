//
//  TableExampleFactory.swift
//  TPPDF_Example
//
//  Created by Philip Niedertscheider on 16.12.19.
//  Copyright © 2019 techprimate GmbH & Co. KG. All rights reserved.
//

import UIKit
import TPPDF

class TableExampleFactory: ExampleFactory {

    func generateDocument() -> [PDFDocument] {
        let document = PDFDocument(format: .a4)

        // Create a table
        let table = PDFTable(rows: 10, columns: 4)

        // Tables can contain Strings, Numbers, Images or nil, in case you need an empty cell.
        // If you add a unknown content type, an assertion will be thrown and the rendering will stop.
        table.content = [
            [nil, "Name",      "Image",                        "Description"],
            [1,   "Waterfall", UIImage(named: "Image-1.jpg")!, "Water flowing down stones."],
            [2,   "Forrest",   UIImage(named: "Image-2.jpg")!, "Sunlight shining through the leafs."],
            [3,   "Fireworks", UIImage(named: "Image-3.jpg")!, "Fireworks exploding into 100.000 stars"],
            [4,   "Fields",    UIImage(named: "Image-4.jpg")!, "Crops growing big and providing food."],
            [1,   "Waterfall", UIImage(named: "Image-1.jpg")!, "Water flowing down stones."],
            [2,   "Forrest",   UIImage(named: "Image-2.jpg")!, "Sunlight shining through the leafs."],
            [3,   "Fireworks", UIImage(named: "Image-3.jpg")!, "Fireworks exploding into 100.000 stars"],
            [4,   "Fields",    UIImage(named: "Image-4.jpg")!, "Crops growing big and providing food."],
            [nil, nil,         nil,                            "Many beautiful places"]
        ]
        table.rows.allRowsAlignment = [.center, .left, .center, .right]

        // The widths of each column is proportional to the total width, set by a value between 0.0 and 1.0, representing percentage.

        table.widths = [
            0.1, 0.25, 0.35, 0.3
        ]

        // To speed up table styling, use a default and change it

        let style = PDFTableStyleDefaults.simple

        // Change standardized styles
        style.footerStyle = PDFTableCellStyle(
            colors: (
                fill: UIColor(red: 0.171875,
                              green: 0.2421875,
                              blue: 0.3125,
                              alpha: 1.0),
                text: UIColor.white
            ),
            borders: PDFTableCellBorders(left: PDFLineStyle(type: .full),
                                         top: PDFLineStyle(type: .full),
                                         right: PDFLineStyle(type: .full),
                                         bottom: PDFLineStyle(type: .full)),

            font: UIFont.systemFont(ofSize: 10)
        )

        // Simply set the amount of footer and header rows

        style.columnHeaderCount = 1
        style.footerCount = 1

        table.style = style

        // Style each cell individually
        
        table[1,1].style = PDFTableCellStyle(colors: (fill: UIColor.yellow, text: UIColor.black))

        // Set table padding and margin
        table.padding = 5.0
        table.margin = 10.0

        // In case of a linebreak during rendering we want to have table headers on each page.

        table.showHeadersOnEveryPage = true

        document.add(table: table)

        return [document]
    }
}
