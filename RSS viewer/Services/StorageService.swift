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
    var lastUpdate: Date?
    
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
    
    func updateAllFeeds() async throws {
        if lastUpdate == nil || lastUpdate?.timeIntervalSinceNow ?? 0 > 900 {
            lastUpdate = Date()
            let request: NSFetchRequest<Feed> = Feed.fetchRequest()
            let feeds = try context.fetch(request)
            for feed in feeds {
                try await saveFeed(feed.url!)
            }
        }
    }
    
    // MARK: Parser
    func parseFeed(from data: Data, feed: Feed) async throws {
        let parser = XMLParser(data: data)
        let rssParserDelegate = RSSParserDelegate(feed: feed, context: context, networkService: networkService)
        
        parser.delegate = rssParserDelegate
        parser.parse()
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
    let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss z",
            "EEE, dd MMM yyyy HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss"
        ]
        
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()
    
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
            case "pubDate":
                for formatter in dateFormatters {
                    if let date = formatter.date(from: currentData) {
                        currentItem?.publishedAt = date
                        break
                    }
                }
            default:
                break
            }
        }
        
        if elementName == "item" {
            if let link = currentItem?.link {
                let predicateLink = NSPredicate(format: "link == %@", link)
                let predicateID = NSPredicate(format: "id != %@", currentItem!.id! as CVarArg)
                let filtredNSSet = feed.items?.filtered(using: NSCompoundPredicate(andPredicateWithSubpredicates: [predicateLink, predicateID]))
                
                if let foundItem = filtredNSSet?.first as? Item {
                    foundItem.title = currentItem?.title
                    foundItem.summary = currentItem?.summary
                    if let pubDate = currentItem?.publishedAt {
                        foundItem.publishedAt = pubDate
                    }
                    context.delete(currentItem!)
                }
            }
            currentItem = nil
        }
    }
}
