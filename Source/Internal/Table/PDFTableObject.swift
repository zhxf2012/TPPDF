//
//  PDFTableObject.swift
//  TPPDF
//
//  Created by Philip Niedertscheider on 12/08/2017.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// swiftlint:disable function_parameter_count

internal typealias PDFTableCalculatedCell = (cell: PDFTableCell,
                                             type: PDFTableObject.CellType,
                                             style: PDFTableCellStyle,
                                             frames: (cell: CGRect, content: CGRect))

/**
 Internal object, used for calculating a `PDFTable`
 */
internal class PDFTableObject: PDFRenderObject {

    /**
     Reference to table
     */
    internal var table: PDFTable

    /**
     Initializer

     - parameter table: Table to calculate and draw
     */
    internal init(table: PDFTable) {
        self.table = table
    }

    /**
     - throws: `PDFError` if table validation fails. See `PDFTableValidator.validateTableData(::)` for details
     */
    override internal func calculate(generator: PDFGenerator, container: PDFContainer) throws -> [PDFLocatedRenderObject] {
        try PDFTableValidator.validateTable(table: table)

        // Calculate available size on current page
        let availableSize = PDFCalculations.calculateAvailableFrame(for: generator, in: container)

        // Calculate position on page
        let tableOrigin = PDFCalculations.calculateElementPosition(for: generator, in: container, with: availableSize)

        // Merge table cells
        let mergeNodes = PDFTableMergeUtil.calculateMerged(table: table)

        // Current vertical position per column
        var verticalOrigins = [tableOrigin.y] + table.cells.indices.map { _ in tableOrigin.y }

        // Calculated cells with their frames
        var cells: [[PDFTableCalculatedCell]] = []

        for (rowIdx, row) in mergeNodes.enumerated() {
            var calculatedCells: [PDFTableCalculatedCell] = []
            for node in row {
                // All previous column widths reduced to single coordinate
                let originX = table.widths[..<node.position.column].reduce(0, +) * availableSize.width
                // Calculate origin of cell offsetted by table origin
                let origin = CGPoint(x: tableOrigin.x + originX, y: verticalOrigins[node.position.row])
                // Column indicies of merged cells, as it might span multiple columns
                let columns = node.position.column...(node.position.column + node.moreColumnsSpan)
                // Width of merged cells
                let width = table.widths[columns].reduce(0, +) * availableSize.width

                // Fetch type of cell
                let type = getCellType(of: node, in: table, at: rowIdx)
                // Fetch style of cell based on type
                let style = getStyle(tableStyle: table.style, type: type)
                // Calculate cell frame
                let cell = calculate(generator: generator,
                                     container: container,
                                     cell: node.cell,
                                     style: style,
                                     type: type,
                                     origin: origin,
                                     width: width)
                calculatedCells.append(cell)

                // Increase bottom offset for columns
                let bottomIndex = node.position.row + node.moreRowsSpan + 1
                verticalOrigins[bottomIndex] = max(verticalOrigins[bottomIndex], cell.frames.cell.maxY)
            }
            cells.append(calculatedCells)
        }

        // Iterate each row of merged cells
        for (rowIdx, row) in mergeNodes.enumerated() {
            // Iterate each merged cell
            for (colIdx, node) in row.enumerated() {
                var frame = cells[rowIdx][colIdx]
                // Align bottom border with other columns
                let bottomIndex = node.position.row + node.moreRowsSpan + 1
                let diffY = verticalOrigins[bottomIndex] - frame.frames.cell.maxY
                frame.frames.cell.size.height += diffY

                // Reposition cell content
                cells[rowIdx][colIdx] = reposition(cell: frame)
            }
        }

        // If column headers should be on every page, we prepare them for repeated use
        var headerHeight: CGFloat = 0
        var headerCells: [PDFTableCalculatedCell] = []
        if table.showHeadersOnEveryPage {
            var rowIdx = 0
            while cells[rowIdx].allSatisfy({ $0.type == .rowHeader || $0.type == .header }) && rowIdx < table.size.rows {
                headerCells += cells[rowIdx]
                rowIdx += 1
            }

            headerHeight = cells[rowIdx].reduce(0, { (prev, calcCell) in
                max(prev, calcCell.frames.cell.minY)
            }) - headerCells.reduce(CGFloat.greatestFiniteMagnitude, { (prev, calcCell) in
                min(prev, calcCell.frames.cell.minY)
            })
        }

        // Create render objects
        let renderObjects = try createRenderObjects(generator: generator,
                                                    container: container,
                                                    cells: cells.reduce([], +),
                                                    headerCells: headerCells,
                                                    headerHeight: headerHeight)

        // Set correct offset of generator
        let finalOffset = PDFCalculations.calculateContentOffset(for: generator, of: renderObjects.offset, in: container)
        try PDFOffsetObject(offset: finalOffset).calculate(generator: generator, container: container)

        return renderObjects.objects
    }

    internal func calculate(generator: PDFGenerator,
                            container: PDFContainer,
                            cell: PDFTableCell,
                            style: PDFTableCellStyle,
                            type: CellType,
                            origin: CGPoint,
                            width: CGFloat) -> PDFTableCalculatedCell {
        var frame = (
            cell: cell,
            style: style,
            type: type,
            frames: (
                cell: CGRect(
                    origin: origin + table.margin,
                    size: CGSize(
                        width: width - 2 * table.margin,
                        height: 0
                    )
                ),
                content: CGRect(
                    origin: origin + table.margin + table.padding,
                    size: CGSize(
                        width: width - 2 * (table.margin + table.padding),
                        height: 0
                    )
                )
            )
        )
        guard let content = cell.content else {
            return frame
        }

        let result = calculate(content: content,
                               style: style,
                               cell: cell,
                               generator: generator,
                               container: container,
                               contentOrigin: frame.frames.content.origin,
                               contentWidth: frame.frames.content.width)

        frame.frames.content.size = result.size
        frame.frames.cell.size.height = result.height + 2 * table.padding

        return frame
    }

    internal func calculate(content: PDFTableContent,
                            style: PDFTableCellStyle,
                            cell: PDFTableCell,
                            generator: PDFGenerator,
                            container: PDFContainer,
                            contentOrigin: CGPoint,
                            contentWidth: CGFloat) -> CGRect {
        if let text = getAttributedStringOfTable(content: content, style: style, alignment: cell.alignment) {
            return PDFCalculations
                .calculateCellFrame(generator: generator,
                                    container: container,
                                    position: (origin: contentOrigin, width: contentWidth),
                                    text: text,
                                    alignment: cell.alignment)
        }
        if let image = content.imageValue {
            return PDFCalculations
                .calculateCellFrame(generator: generator,
                                    origin: contentOrigin,
                                    width: contentWidth,
                                    image: image)
        }
        return CGRect.zero
    }

    internal func getAttributedStringOfTable(content: PDFTableContent,
                                             style: PDFTableCellStyle,
                                             alignment: PDFTableCellAlignment) -> NSAttributedString? {
        if let stringText = content.stringValue {
            return createAttributedCellText(text: stringText, cellStyle: style, alignment: alignment)
        }
        return content.attributedStringValue
    }

    internal func reposition(cell: PDFTableCalculatedCell) -> PDFTableCalculatedCell {
        var result = cell

        result.frames.content.origin.x = repositionX(of: cell)
        result.frames.content.origin.y = repositionY(of: cell)

        return result
    }

    internal func repositionX(of calculatedCell: PDFTableCalculatedCell) -> CGFloat {
        let alignment = calculatedCell.cell.alignment
        let frame = calculatedCell.frames

        if alignment.isLeft {
            return frame.content.minX
        }
        if alignment.isRight {
            return frame.content.minX + frame.cell.width - 2 * table.padding - frame.content.width
        }
        return frame.content.minX + (frame.cell.width - 2 * table.padding - frame.content.width) / 2
    }

    internal func repositionY(of calculatedCell: PDFTableCalculatedCell ) -> CGFloat {
        let alignment = calculatedCell.cell.alignment
        let frame = calculatedCell.frames

        if alignment.isTop {
            return frame.content.minY
        }
        if alignment.isBottom {
            return frame.content.minY + frame.cell.height - 2 * table.padding - frame.content.height
        }
        return frame.content.minY + (frame.cell.height - 2 * table.padding - frame.content.height) / 2
    }

    /**
     TODO: Documentation
     */
    internal func createAttributedCellText(text: String, cellStyle: PDFTableCellStyle, alignment: PDFTableCellAlignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = {
            if alignment.isLeft {
                return .left
            }
            if alignment.isRight {
                return .right
            }
            return .center
        }()

        let attributes: [NSAttributedString.Key: AnyObject] = [
            .foregroundColor: cellStyle.colors.text,
            .font: cellStyle.font,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    /**
     TODO: Documentation
     */
    internal func createRenderObjects(generator: PDFGenerator,
                                      container: PDFContainer,
                                      cells: [PDFTableCalculatedCell],
                                      headerCells: [PDFTableCalculatedCell]?,
                                      headerHeight: CGFloat) throws -> (objects: [PDFLocatedRenderObject], offset: CGFloat) {
        var result: [PDFLocatedRenderObject] = []

        var firstPage = true
        let startPosition: CGPoint = cells.first?.frames.cell.origin ?? .zero
        var nextPageCells: [PDFTableCalculatedCell] = cells
        var pageEnd = CGPoint.null

        repeat {
            var pageStart = CGPoint.null

            var minOffset = PDFCalculations.calculateTopMinimum(for: generator)
            let maxOffset = PDFCalculations.calculateBottomMaximum(for: generator)

            if !firstPage, let headerCells = headerCells {
                for item in headerCells {
                    var cellFrame = item.frames.cell
                    var contentFrame = item.frames.content
                    cellFrame.origin.y -= startPosition.y - minOffset
                    contentFrame.origin.y -= startPosition.y - minOffset

                    pageStart = pageStart == .null ? cellFrame.origin : pageStart
                    pageEnd = CGPoint(x: cellFrame.maxX, y: cellFrame.maxY) + CGPoint(x: table.margin, y: table.margin)

                    var cellElements = [PDFRenderObject]()

                    // Background
                    cellElements += [createCellBackgroundObject(style: item.style, frame: cellFrame)]

                    // Content
                    if let contentObj = createCellContentObject(content: item.cell.content,
                                                                style: item.style,
                                                                alignment: item.cell.alignment,
                                                                frame: contentFrame) {
                        cellElements.append(contentObj)
                    }

                    // Grid
                    let outline = try createCellOutlineObjects(borders: item.style.borders, frame: cellFrame)
                        .map({ try $0.calculate(generator: generator, container: container) })
                        .reduce([], +)
                        .map(\.1)
                    cellElements += outline

                    let sliceObject = createSliceObject(frame: cellFrame,
                                                        elements: cellElements,
                                                        minOffset: minOffset,
                                                        maxOffset: maxOffset)
                    result += try sliceObject.calculate(generator: generator, container: container)
                }
                minOffset +=  headerHeight
            }

            var onPageCells: [PDFTableCalculatedCell]
            (onPageCells, nextPageCells) = filterCellsOnPage(for: generator, items: nextPageCells, minOffset: minOffset, maxOffset: maxOffset)

            for (idx, item) in onPageCells.enumerated() {
                let cellFrame = item.frames.cell

                if pageStart == CGPoint.null {
                    pageStart = cellFrame.origin - CGPoint(x: table.margin, y: table.margin)
                }
                pageEnd = CGPoint(x: cellFrame.maxX, y: cellFrame.maxY) + CGPoint(x: table.margin, y: table.margin)

                var cellElements = [PDFRenderObject]()

                // Background
                cellElements.append(createCellBackgroundObject(style: item.style, frame: cellFrame))

                // Content
                if let contentObj = createCellContentObject(content: item.cell.content,
                                                            style: item.style,
                                                            alignment: item.cell.alignment,
                                                            frame: item.frames.content) {
                    cellElements.append(contentObj)
                }

                // Grid
                let outline = try createCellOutlineObjects(borders: item.style.borders, frame: cellFrame)
                    .map({ try $0.calculate(generator: generator, container: container) })
                    .reduce([], +)
                    .map(\.1)
                cellElements += outline
                
                let sliceObject = createSliceObject(frame: cellFrame,
                                                    elements: cellElements,
                                                    minOffset: minOffset,
                                                    maxOffset: maxOffset)
                result += try sliceObject.calculate(generator: generator, container: container)

                if nextPageCells.isEmpty && idx == cells.count - 1 {
                    let tableOutlineObject = PDFRectangleObject(lineStyle: table.style.outline, size: CGSize.zero)
                    tableOutlineObject.frame = CGRect(
                        x: pageStart.x,
                        y: pageStart.y,
                        width: pageEnd.x - pageStart.x,
                        height: pageEnd.y - pageStart.y
                    )
                    result += try tableOutlineObject.calculate(generator: generator, container: container)
                }
            }
            if !nextPageCells.isEmpty {
                result += try PDFPageBreakObject().calculate(generator: generator, container: container)
                firstPage = false
                pageEnd = .null
            }
        } while !nextPageCells.isEmpty
        return (objects: result, offset: pageEnd.y)
    }

    internal typealias FilteredCells = (cells: [PDFTableCalculatedCell], rest: [PDFTableCalculatedCell])

    internal func filterCellsOnPage(for generator: PDFGenerator, items: [PDFTableCalculatedCell], minOffset: CGFloat, maxOffset: CGFloat) -> FilteredCells {
        let contentHeight = maxOffset - minOffset

        var cells: [PDFTableCalculatedCell] = []
        var rest: [PDFTableCalculatedCell] = []

        for item in  items {
            let cellFrame = item.frames.cell
            if cellFrame.maxY < maxOffset {
                cells.append(item)
            } else {
                if cellFrame.minY < maxOffset {
                    cells.append(item)
                }
                var nextPageCell = item
                nextPageCell.frames.cell.origin.y -= contentHeight
                nextPageCell.frames.content.origin.y -= contentHeight
                rest.append(nextPageCell)
            }
        }
        return (cells: cells, rest: rest)
    }

    internal func createSliceObject(frame: CGRect, elements: [PDFRenderObject], minOffset: CGFloat, maxOffset: CGFloat) -> PDFSlicedObject {
        let sliceObject = PDFSlicedObject(children: elements, frame: frame)
        if frame.maxY > maxOffset {
            sliceObject.frame.size.height -= sliceObject.frame.maxY - maxOffset
            sliceObject.frame.size.height = min(sliceObject.frame.size.height, maxOffset - minOffset)
        }
        if frame.minY < minOffset {
            sliceObject.frame.origin.y += minOffset - sliceObject.frame.origin.y
            sliceObject.frame.size.height -= minOffset - sliceObject.frame.origin.y
        }
        return sliceObject
    }

    /**
     Creates a render object for the cell background
     */
    internal func createCellBackgroundObject(style: PDFTableCellStyle, frame: CGRect) -> PDFRenderObject {
        let object = PDFRectangleObject(lineStyle: .none, size: frame.size, fillColor: style.colors.fill)
        object.frame = frame
        return object
    }

    /**
     Creates the render object for the cell content
     */
    internal func createCellContentObject(content: PDFTableContent?, style: PDFTableCellStyle,
                                          alignment: PDFTableCellAlignment, frame: CGRect) -> PDFRenderObject? {
        guard let content = content else {
            return nil
        }
        var contentObject: PDFRenderObject?

        if let contentImage = content.imageValue {
            contentObject = PDFImageObject(image: PDFImage(image: contentImage, options: [.none]))
        } else {
            var attributedString: NSAttributedString?
            if let contentText = content.stringValue {
                attributedString = createAttributedCellText(text: contentText, cellStyle: style, alignment: alignment)
            } else if let contentText = content.attributedStringValue {
                attributedString = contentText
            }

            if let string = attributedString {
                let textObject = PDFAttributedTextObject(attributedText: PDFAttributedText(text: string))
                textObject.attributedString = string
                contentObject = textObject
            }
        }
        contentObject?.frame = frame

        return contentObject
    }

    internal enum CellType: Equatable {

        case header
        case footer
        case rowHeader
        case alternatingRow
        case content
        case custom(style: PDFTableCellStyle)

    }

    internal func getCellType(of node: PDFTableNode, in table: PDFTable, at rowIdx: Int) -> CellType {
        if let style = node.cell.style {
            return .custom(style: style)
        }
        if rowIdx < table.style.columnHeaderCount {
            return .header
        }
        if rowIdx >= table.cells.count - table.style.footerCount {
            return .footer
        }
        if node.position.column < table.style.rowHeaderCount {
            return .rowHeader
        }
        if rowIdx % 2 == 1 {
            return .alternatingRow
        }
        return .content
    }

    /**
     Returns the style of a given cell, depending on the type.

     - parameters tableStyle: Style configuration of table
     - parameters type: Type of cell

     - returns: Style of cell
     */
    internal func getStyle(tableStyle: PDFTableStyle, type: CellType) -> PDFTableCellStyle {
        switch type {
        case .header:
            return tableStyle.columnHeaderStyle
        case .footer:
            return tableStyle.footerStyle
        case .rowHeader:
            return tableStyle.rowHeaderStyle
        case .alternatingRow:
            return tableStyle.alternatingContentStyle ?? tableStyle.contentStyle
        case .custom(let style):
            return style
        default:
            return tableStyle.contentStyle
        }
    }

    /**
     Creates four outline line objects around a given frame using the given style.

     - parameter borders: Style of each border direction
     - parameter frame: Frame of rectangle

     - returns: Array of `PDFLineObject`
     */
    internal func createCellOutlineObjects(borders: PDFTableCellBorders, frame: CGRect) -> [PDFLineObject] {
        [
            PDFLineObject(style: borders.top,
                          startPoint: CGPoint(x: frame.minX, y: frame.minY),
                          endPoint: CGPoint(x: frame.maxX, y: frame.minY)),
            PDFLineObject(style: borders.bottom,
                          startPoint: CGPoint(x: frame.minX, y: frame.maxY),
                          endPoint: CGPoint(x: frame.maxX, y: frame.maxY)),
            PDFLineObject(style: borders.right,
                          startPoint: CGPoint(x: frame.maxX, y: frame.minY),
                          endPoint: CGPoint(x: frame.maxX, y: frame.maxY)),
            PDFLineObject(style: borders.left,
                          startPoint: CGPoint(x: frame.minX, y: frame.minY),
                          endPoint: CGPoint(x: frame.minX, y: frame.maxY))
        ]
    }

    /**
     Creates a new `PDFTableObject` with the same properties
     */
    override internal var copy: PDFRenderObject {
        PDFTableObject(table: table.copy)
    }
}
