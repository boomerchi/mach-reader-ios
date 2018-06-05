//
//  PdfReaderViewController.swift
//  MachReader
//
//  Created by ShuichiNagao on 2018/05/25.
//  Copyright © 2018 mach-technologies. All rights reserved.
//

import UIKit
import PDFKit
import Pring
import NVActivityIndicatorView

class PdfReaderViewController: UIViewController {

    // MARK: - Properties
    
    @IBOutlet private weak var pdfView: PDFView!
    @IBOutlet private weak var pdfThumbnailView: PDFThumbnailView!
    
    private var book: Book!
    private var visibleHighlights: Set<Highlight> = []
    
    private var currentPageNumber: Int {
        let page = pdfView.currentPage
        return pdfView.document?.index(for: page!) ?? 0
    }
    
    // MARK: - Initialize method
    
    static func instantiate(book: Book) -> PdfReaderViewController {
        let sb = UIStoryboard(name: "PdfReader", bundle: nil)
        let vc = sb.instantiateInitialViewController() as! PdfReaderViewController
        vc.book = book
        return vc
    }
    
    // MARK: - Life cycle methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        startAnimating(type: .circleStrokeSpin)
        
        NotificationObserver.add(name: .PDFViewAnnotationHit, method: handleHitAnnotation)
        NotificationObserver.add(name: .PDFViewPageChanged, method: handlePageChanged)
        
        setupDocument()
        setupPDFView()
        createMenu()
        
        drawStoredHighlights()

        stopAnimating()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        NotificationObserver.removeAll(from: self)
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(highlightAction(_:)) {
            return true
        } else if action == #selector(comment(_:)) {
            return true
        }
        return false
    }
    
    // MARK: - private methods
    
    /// PDF data handling for init
    private func setupDocument() {
        guard let url = book.contents?.downloadURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let document = PDFDocument(data: data) else { return }
        pdfView.document = document
        
        if book.thumbnail?.downloadURL != nil { return }

        guard let attr = document.documentAttributes else { return }
        book.title = attr["Title"] as? String
        book.author = attr["Author"] as? String
        guard let page1 = document.page(at: 0) else { return }
        let uiImage = page1.thumbnail(of: CGSize(width: 400, height: 400 / 0.7), for: .artBox)
        guard let imageData = UIImagePNGRepresentation(uiImage) else { return }
        book.thumbnail = File(data: imageData, mimeType: .png)
        book.isPublic = false
        book.update()
    }
    
    /// Base settings for PDFView.
    private func setupPDFView() {
        pdfView.backgroundColor = .lightGray
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .horizontal
        pdfView.usePageViewController(true)
        
        pdfThumbnailView.pdfView = pdfView
        pdfThumbnailView.layoutMode = .horizontal
        pdfThumbnailView.backgroundColor = UIColor.gray
    }

    /// Customize UIMenuController.
    private func createMenu() {
        let highlightItem = UIMenuItem(title: "Highlight", action: #selector(highlightAction(_:)))
        let commentItem = UIMenuItem(title: "Comment", action: #selector(comment(_:)))
        UIMenuController.shared.menuItems = [highlightItem, commentItem]
    }
    
    /// Notification handler for hitting of annotation, such as an existing highlight.
    @objc private func handleHitAnnotation(notification: Notification) {
        guard let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFAnnotation else { return }
        guard let h = Highlight.filter(visibleHighlights, withBounds: annotation.bounds) else { return }
        
        let vc = CommentsViewController.instantiate(highlight: h)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }
    
    /// Notification handler for the current page change.
    @objc private func handlePageChanged(notification: Notification) {
        visibleHighlights = []
        drawStoredHighlights()
    }
    
    /// Fetch Highlights stored at Firestore and display those annotation views.
    private func drawStoredHighlights() {
        book?.getHighlights() { [weak self] highlight, error in
            guard let `self` = self else { return }
            guard let h = highlight else { return }
            
            if h.page == self.currentPageNumber {
                guard let selection = self.pdfView.document?.findString(h.text ?? "", withOptions: .caseInsensitive).first else { return }
                guard let page = selection.pages.first else { return }
                self.visibleHighlights.insert(h)
                self.addHighlightView(selection: selection, page: page)
            }
        }
    }
    
    /// Add highlight annotation view.
    private func addHighlightView(selection: PDFSelection, page: PDFPage) {
        selection.selectionsByLine().forEach { s in
            let highlight = PDFAnnotation(bounds: s.bounds(for: page), forType: .highlight, withProperties: nil)
            highlight.endLineStyle = .square
            page.addAnnotation(highlight)
        }
    }
    
    /// Call above method and save this Highlight at Firestore.
    @objc private func highlightAction(_ sender: UIMenuController?) {
        guard let currentSelection = pdfView.currentSelection else { return }
        guard let page = currentSelection.pages.first else { return }
        
        addHighlightView(selection: currentSelection, page: page)
        pdfView.clearSelection()
        
        let h = book.saveHighlight(text: currentSelection.string, pageNumber: currentPageNumber, bounds: currentSelection.bounds(for: page))
        if h != nil { visibleHighlights.insert(h!) }
    }
    
    /// Go to AddCommentViewController to save both Highlight and Comment.
    @objc private func comment(_ sender: UIMenuController?) {
        guard let currentSelection = pdfView.currentSelection else { return }
        guard let page = currentSelection.pages.first else { return }
        guard let text = currentSelection.string else { return }
        guard let pageNumber = pdfView.document?.index(for: page) else { return }
        
        pdfView.clearSelection()

        let h = Highlight.new(text: text, page: pageNumber, bounds: currentSelection.bounds(for: page))
        let vc = AddCommentViewController.instantiate(highlight: h, book: book) { [weak self] in
            self?.addHighlightView(selection: currentSelection, page: page)
            self?.visibleHighlights.insert(h)
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet

        present(nav, animated: true)
    }
}

// MARK: - NVActivityIndicatorViewable
extension PdfReaderViewController: NVActivityIndicatorViewable {}
