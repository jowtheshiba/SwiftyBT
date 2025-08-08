import Foundation

func printUsage() {
    print("SwiftyBT - Torrent File and Magnet Link Parser")
    print()
    print("Usage:")
    print("  swift run SwiftyBT <torrent_file_path>")
    print("  swift run SwiftyBT <magnet_link>")
    print()
    print("Examples:")
    print("  swift run SwiftyBT /path/to/file.torrent")
    print("  swift run SwiftyBT \"magnet:?xt=urn:btih:...\"")
    print()
    print("Options:")
    print("  --detailed    Show detailed information (for torrent files)")
    print("  --dht         Search for DHT trackers")
    print("  --help        Show this help message")
}

func parseArguments() -> (input: String, detailed: Bool, dht: Bool) {
    let arguments = CommandLine.arguments.dropFirst() // Пропускаем имя программы
    
    if arguments.isEmpty {
        print("Error: No input provided")
        printUsage()
        exit(1)
    }
    
    var input: String?
    var detailed = false
    var dht = false
    
    for argument in arguments {
        switch argument {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--detailed":
            detailed = true
        case "--dht":
            dht = true
        default:
            if input == nil {
                input = argument
            } else {
                print("Error: Multiple inputs provided")
                printUsage()
                exit(1)
            }
        }
    }
    
    guard let input = input else {
        print("Error: No input provided")
        printUsage()
        exit(1)
    }
    
    return (input, detailed, dht)
}

@available(iOS 13.0, macOS 10.15, *)
func processInput(_ input: String, detailed: Bool, dht: Bool) {
    print("SwiftyBT - Torrent Parser")
    print("Processing: \(input)")
    print()
    
    // Проверяем, является ли это magnet ссылкой
    if MagnetParser.isMagnetLink(input) {
        do {
            let magnetLink = try MagnetParser.parseMagnetLink(input)
            MagnetParser.printMagnetInfo(magnetLink)
            
            if dht {
                searchDHTTrackers(for: magnetLink)
                
            }
        } catch {
            print("Error parsing magnet link: \(error)")
            exit(1)
        }
    } else {
        // Пытаемся обработать как torrent файл
        do {
            let torrentFile = try TorrentParser.parseTorrentFile(at: input)
            if detailed {
                TorrentParser.printDetailedTorrentInfo(torrentFile)
            } else {
                TorrentParser.printTorrentInfo(torrentFile)
            }
            
            if dht {
                searchDHTTrackers(for: torrentFile)
                
            }
        } catch {
            print("Error parsing torrent file: \(error)")
            print()
            print("Make sure the file exists and is a valid .torrent file")
            exit(1)
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
func searchDHTTrackers(for magnetLink: MagnetLink) {
    print("\n🔍 Starting DHT tracker search for magnet link...")
    print("💡 DHT search is running...")
    print("📊 Found trackers will be displayed below:")
    print("🔗 Magnet: \(magnetLink.displayName ?? "Unknown")")
    print("🆔 Info Hash: \(magnetLink.infoHash)")
    print(String(repeating: "─", count: 50))
    
    let dhtProvider = DHTTrackersProvider()
    dhtProvider.searchTrackers(for: magnetLink) { trackers in
        print("\n" + String(repeating: "─", count: 50))
        print("✅ DHT search completed!")
        print("🔗 Magnet: \(magnetLink.displayName ?? "Unknown")")
        print("📊 Total found: \(trackers.count) DHT trackers")
        
        if trackers.isEmpty {
            print("❌ No DHT trackers found for this magnet link")
            print("💡 This could mean:")
            print("   • The torrent is not active in DHT network")
            print("   • No peers are currently sharing this torrent")
            print("   • The torrent uses private trackers only")
        } else {
            print("✅ Found DHT trackers for your magnet link:")
            for (index, tracker) in trackers.enumerated() {
                print("   \(index + 1). \(tracker.trackerURL) (\(tracker.trackerType))")
            }
        }
        
        // Останавливаем поиск
        dhtProvider.stopSearch()
        
        // Завершаем программу после поиска
        DispatchQueue.main.async {
            exit(0)
        }
    }
    
    // Держим программу запущенной
    print("⏳ Waiting for DHT trackers... (Press Ctrl+C to stop)")
    RunLoop.main.run()
}

@available(iOS 13.0, macOS 10.15, *)
func searchDHTTrackers(for torrentFile: TorrentFile) {
    print("\n🔍 Starting DHT tracker search for torrent file...")
    print("💡 DHT search is running...")
    print("📊 Found trackers will be displayed below:")
    print("📁 Torrent: \(torrentFile.info.name)")
    print("📏 Size: \(formatBytes(torrentFile.info.length ?? 0))")
    print(String(repeating: "─", count: 50))
    
    let dhtProvider = DHTTrackersProvider()
    dhtProvider.searchTrackers(for: torrentFile) { trackers in
        print("\n" + String(repeating: "─", count: 50))
        print("✅ DHT search completed!")
        print("📁 Torrent: \(torrentFile.info.name)")
        print("📊 Total found: \(trackers.count) DHT trackers")
        
        if trackers.isEmpty {
            print("❌ No DHT trackers found for this torrent")
            print("💡 This could mean:")
            print("   • The torrent is not active in DHT network")
            print("   • No peers are currently sharing this torrent")
            print("   • The torrent uses private trackers only")
        } else {
            print("✅ Found DHT trackers for your torrent:")
            for (index, tracker) in trackers.enumerated() {
                print("   \(index + 1). \(tracker.trackerURL) (\(tracker.trackerType))")
            }
        }
        
        // Останавливаем поиск
        dhtProvider.stopSearch()
        
        // Завершаем программу после поиска
        DispatchQueue.main.async {
            exit(0)
        }
    }
    
    // Держим программу запущенной
    print("⏳ Waiting for DHT trackers... (Press Ctrl+C to stop)")
    RunLoop.main.run()
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB, .useKB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

// Основная логика программы


if #available(iOS 13.0, macOS 10.15, *) {
    let (input, detailed, dht) = parseArguments()
    processInput(input, detailed: detailed, dht: dht)
} else {
    // Fallback on earlier versions
}

