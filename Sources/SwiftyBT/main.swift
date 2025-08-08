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
                if #available(macOS 10.15, *) {
                    searchDHTTrackers(for: magnetLink)
                } else {
                    print("❌ DHT search requires macOS 10.15 or later")
                    exit(1)
                }
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
                if #available(macOS 10.15, *) {
                    searchDHTTrackers(for: torrentFile)
                } else {
                    print("❌ DHT search requires macOS 10.15 or later")
                    exit(1)
                }
            }
        } catch {
            print("Error parsing torrent file: \(error)")
            print()
            print("Make sure the file exists and is a valid .torrent file")
            exit(1)
        }
    }
}

@available(macOS 10.15, *)
func searchDHTTrackers(for magnetLink: MagnetLink) {
    print("\n🔍 Starting DHT tracker search for magnet link...")
    print("💡 DHT search is running...")
    print("📊 Found trackers will be displayed below:")
    print(String(repeating: "─", count: 50))
    
    let dhtProvider = DHTTrackersProvider()
    dhtProvider.searchTrackers(for: magnetLink) { trackers in
        print("\n" + String(repeating: "─", count: 50))
        print("✅ DHT search completed!")
        print("📊 Total found: \(trackers.count) DHT trackers")
        
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

@available(macOS 10.15, *)
func searchDHTTrackers(for torrentFile: TorrentFile) {
    print("\n🔍 Starting DHT tracker search for torrent file...")
    print("💡 DHT search is running...")
    print("📊 Found trackers will be displayed below:")
    print(String(repeating: "─", count: 50))
    
    let dhtProvider = DHTTrackersProvider()
    dhtProvider.searchTrackers(for: torrentFile) { trackers in
        print("\n" + String(repeating: "─", count: 50))
        print("✅ DHT search completed!")
        print("📊 Total found: \(trackers.count) DHT trackers")
        
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

// Основная логика программы
let (input, detailed, dht) = parseArguments()
processInput(input, detailed: detailed, dht: dht)

