//
//  StorageService.swift
//  RSS viewer
//
//  Created by Андрей Валянский on 16.01.2026.
//

import CoreData

class StorageService { // Store data in CoreData
    let container = NSPersistentContainer(name: "RSS_viewer")
    let networkService = NetworkService()
    
    lazy var context: NSManagedObjectContext = container.viewContext
    
    init() {
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Не удалось загрузить CoreData: \(error)")
            }
        }
    }
    
    // MARK: Operations with feeds
    func saveFeed(_ urlString: String) async throws { // If feed already exists function update it, else adds new feed
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "InvalidURL", code: 1, userInfo: nil)
        }
        
        guard let data: Data = try? await networkService.fetch(url: url) else {
            throw NSError(domain: "NetworkError", code: 2, userInfo: nil)
        }
        
        let feed: Feed
        
        let request: NSFetchRequest<Feed> = Feed.fetchRequest()
        request.predicate = NSPredicate(format: "url == %@", urlString)
        request.fetchLimit = 1
        
        if let existingFeed = try context.fetch(request).first {
            feed = existingFeed
        } else {
            feed = Feed(context: context)
            feed.id = UUID()
            feed.url = urlString
        }
        
        try await parseFeed(from: data, feed: feed)
        
        try await MainActor.run {
            try context.save()
        }
    }
    
    func deleteFeed(_ feed: Feed) throws {
        context.delete(feed)
        try context.save()
    }


    // MARK: UI data source
    func feeds() throws -> [feedsListItem] {
        let request: NSFetchRequest<Feed> = Feed.fetchRequest()
        let feeds = try context.fetch(request)
        
        return feeds.compactMap { feed in
            guard let id = feed.id, let title = feed.title, let channelDescription = feed.channelDescription else { return nil }
            
            return feedsListItem(id: id, title: title, channelDescription: channelDescription)
        }
    }
    
    // MARK: Parser
    func parseFeed(from data: Data, feed: Feed) async throws {
        let parser = XMLParser(data: data)
        let rssParserDelegate = RSSParserDelegate(feed: feed, context: context, networkService: networkService)
        
        parser.delegate = rssParserDelegate
        parser.parse()
        
//        try await loadContent(feed: feed)
    }
    
    func loadContent(feed: Feed) async throws {
        guard let items = feed.items as? Set<Item> else { return }
        
        for item in items {
            item.content = String(data: try await networkService.fetch(url: URL(string: item.link!)!), encoding: .utf8)
        }
    }
}

struct feedsListItem {
    let id: UUID
    let title: String
    let channelDescription: String
}

class RSSParserDelegate: NSObject, XMLParserDelegate {
    let feed: Feed
    let context: NSManagedObjectContext
    let networkService: NetworkService
    
    var phase: String = ""
    var currentData: String = ""
    var currentLink: String?
    var currentItem: Item?
    
    init(feed: Feed, context: NSManagedObjectContext, networkService: NetworkService) {
        self.feed = feed
        self.feed.title = "Loading..."
        self.feed.lastFetched = Date()
        self.context = context
        self.networkService = networkService
        
        super.init()
    }

    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentData = ""
        
        switch elementName {
        case "channel":
            phase = elementName
        case "item":
            phase = elementName
            
            currentItem = Item(context: context)
            currentItem?.id = UUID()
            currentItem?.feed = feed
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentData += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if phase == "channel" {
            switch elementName {
            case "title":
                feed.title = currentData
            case "description":
                feed.channelDescription = currentData
            default:
                break
            }
        } else if phase == "item" {
            switch elementName {
            case "title":
                currentItem?.title = currentData
            case "description":
                currentItem?.summary = currentData
            case "link":
                currentItem?.link = currentData
            default:
                break
            }
        }
        
        if elementName == "item" {
            if let link = currentItem?.link {
                let predicate = NSPredicate(format: "link == %@", link)
                let filtredNSSet = feed.items?.filtered(using: predicate)
                
                if let foundItem = filtredNSSet?.first as? Item {
                    currentItem?.id = foundItem.id
                    currentItem?.summary = foundItem.summary
                }
            }
            currentItem = nil
        }
    }
}
