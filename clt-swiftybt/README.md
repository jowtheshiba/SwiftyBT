# clt-swiftybt

[![Version](https://img.shields.io/badge/Version-1.0.0-blue.svg)](https://github.com/your-username/SwiftyBT)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue.svg)](https://swift.org)

A simple command-line torrent downloader built with SwiftyBT.

## 🚀 Features

- **Simple CLI Interface** - Easy to use command-line tool
- **Multiple Torrent Support** - Download multiple torrents simultaneously
- **Progress Display** - Real-time progress bars and statistics
- **Automatic Directory Creation** - Creates `torrent_downloads` folder
- **Cross-Platform** - Works on macOS and Linux

## 📦 Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/your-username/SwiftyBT.git
cd SwiftyBT/clt-swiftybt

# Build the CLI tool
swift build -c release

# Install globally (optional)
cp .build/release/clt-swiftybt /usr/local/bin/
```

### Prerequisites

- Swift 6.0+
- macOS 13.0+ or Linux
- SwiftyBT library (included as dependency)

## 💻 Usage

### Basic Usage

```bash
# Download a single torrent
clt-swiftybt movie.torrent

# Download multiple torrents
clt-swiftybt file1.torrent file2.torrent file3.torrent
```

### Examples

```bash
# Download a movie torrent
clt-swiftybt /path/to/movie.torrent

# Download multiple files
clt-swiftybt *.torrent

# Download from current directory
clt-swiftybt ./downloads/*.torrent
```

## 📁 Output

The tool creates a `torrent_downloads` directory in the current working directory and downloads all torrents there:

```
torrent_downloads/
├── movie.mp4
├── software.zip
└── documents.pdf
```

## 📊 Progress Display

The tool shows real-time progress for each torrent:

```
🌊 SwiftyBT CLI Tool v1.0
==========================
📁 Downloads directory: /path/to/torrent_downloads
📦 Found 2 torrent file(s)

✅ Loaded: Movie Title
   Size: 1.2 GB
   Pieces: 1024

✅ Loaded: Software Package
   Size: 500.0 MB
   Pieces: 512

🚀 Starting downloads...

📥 Movie Title
   [██████████████████████████████] 100%
   📊 1.2 GB / 1.2 GB (2.5 MB/s)
   👥 Peers: 15

📥 Software Package
   [████████████████░░░░░░░░░░░░░░] 60%
   📊 300.0 MB / 500.0 MB (1.8 MB/s)
   👥 Peers: 8

✅ All downloads completed!
```

## 🔧 Options

Currently, the tool accepts `.torrent` files as arguments. Future versions may include:

- `--output-dir` - Specify custom download directory
- `--limit-speed` - Limit download speed
- `--port` - Specify port for incoming connections
- `--verbose` - Enable detailed logging

## 🐛 Troubleshooting

### Common Issues

1. **"No .torrent files provided"**
   - Make sure you're providing `.torrent` files as arguments
   - Check file paths are correct

2. **"Failed to create downloads directory"**
   - Ensure you have write permissions in the current directory
   - Check disk space availability

3. **"Failed to load torrent file"**
   - Verify the `.torrent` file is valid and not corrupted
   - Check file permissions

### Debug Mode

For detailed logging, modify the log level in `main.swift`:

```swift
handler.logLevel = .debug // Change from .warning to .debug
```

## 🤝 Contributing

Contributions are welcome! Please see the main [SwiftyBT contributing guidelines](../CONTRIBUTING.md).

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

---

**clt-swiftybt** - Simple command-line torrent downloader

Built with ❤️ using SwiftyBT 