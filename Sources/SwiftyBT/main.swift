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
    print("  --help        Show this help message")
}

func parseArguments() -> (input: String, detailed: Bool) {
    let arguments = CommandLine.arguments.dropFirst() // Пропускаем имя программы
    
    if arguments.isEmpty {
        print("Error: No input provided")
        printUsage()
        exit(1)
    }
    
    var input: String?
    var detailed = false
    
    for argument in arguments {
        switch argument {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--detailed":
            detailed = true
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
    
    return (input, detailed)
}

func processInput(_ input: String, detailed: Bool) {
    print("SwiftyBT - Torrent Parser")
    print("Processing: \(input)")
    print()
    
    // Проверяем, является ли это magnet ссылкой
    if MagnetParser.isMagnetLink(input) {
        do {
            let magnetLink = try MagnetParser.parseMagnetLink(input)
            MagnetParser.printMagnetInfo(magnetLink)
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
        } catch {
            print("Error parsing torrent file: \(error)")
            print()
            print("Make sure the file exists and is a valid .torrent file")
            exit(1)
        }
    }
}

// Основная логика программы
let (input, detailed) = parseArguments()
processInput(input, detailed: detailed)

