//
//  HighlightListViewModel.swift
//  MachReader
//
//  Created by ShuichiNagao on 2018/06/17.
//  Copyright © 2018 mach-technologies. All rights reserved.
//

import Foundation
import Pring
import Firebase

class HighlightListViewModel {
    private let book: Book
    private var myHighlightDataSource: DataSource<Highlight>?
    private var allHighlightDataSource: DataSource<Highlight>?

    init(book: Book) {
        self.book = book
    }
    
    var highlightsCount: Int {
        return highlightDataSource?.count ?? 0
    }
    
    var highlightDataSource: DataSource<Highlight>? {
        return showOthersHighlightList ? allHighlightDataSource : myHighlightDataSource
    }
    
    var showOthersHighlightList: Bool {
        return UserDefaultsUtil.showOthersHighlightList
    }

    func loadHighlights(completion: @escaping ((QuerySnapshot?, CollectionChange) -> Void)) {
        guard let userID = User.default?.id else { return }
        
        let options: Options = Options()
        let sortDescriptor: NSSortDescriptor = NSSortDescriptor(key: "updatedAt", ascending: false)
        options.sortDescirptors = [sortDescriptor]
        
        if showOthersHighlightList {
            allHighlightDataSource = book.highlights
                .order(by: \Highlight.createdAt)
                .dataSource(options: options)
                .on(parse: { (_, highlight, done) in
                    highlight.comments.get() { (snapshot, comments) in
                        done(highlight)
                    }
                })
                .on() { (snapshot, changes) in
                    completion(snapshot, changes)
                }
                .listen()
        } else {
            myHighlightDataSource = book.highlights
                .where(\Highlight.userID, isEqualTo: userID)
                .order(by: \Highlight.createdAt)
                .dataSource(options: options)
                .on(parse: { (_, highlight, done) in
                    highlight.comments.get() { (snapshot, comments) in
                        done(highlight)
                    }
                })
                .on() { (snapshot, changes) in
                    completion(snapshot, changes)
                }
                .listen()
        }
    }
    
    func highlight(at indexPath: IndexPath) -> Highlight? {
        guard let dataSource = highlightDataSource else { return nil }
        if dataSource.isEmpty { return nil }
        return dataSource[indexPath.item]
    }
    
    func commentText(at indexPath: IndexPath) -> String? {
        guard let comments = highlight(at: indexPath)?.comments else { return nil }
        if comments.isEmpty { return nil }
        var str = ""
        comments.forEach { str.append("\($0.text ?? "")\n") }
        return str
    }
    
    func switchHighlightListRange() {
        UserDefaultsUtil.showOthersHighlightList = !showOthersHighlightList
    }
}
