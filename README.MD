# 📊 API Tracker

A simple and efficient bash script for monitoring API endpoints with real-time status updates, detailed statistics, and configurable analysis modes.

---

## 📋 Features

- **Real-time Monitoring**: Checks API endpoint at specified intervals.
- **Colorful Output**: Console output with colors for easy status identification.
- **Progress Indicator**: Visual progress bar showing monitoring progress.
- **Multiple Analysis Modes**:
  - Mode `0`: Delays only
  - Mode `1`: Errors and delays (default)
  - Mode `2`: Full analysis including response codes
- **Comprehensive Logging**: Detailed logs saved to timestamped files.
- **Statistics Dashboard**: Displays key metrics such as success rate, slow responses, errors, and latency.

---

## 🛠️ Usage

```bash
./run.sh <API_URL> <total_time_minutes> <interval_seconds> <threshold_ms> [timeout_seconds] [analysis_mode]
```

### Example:

```bash
./run.sh "https://api.example.com/endpoint" 30 300 1500 5 1
```

### One-liner Installation and Execution

```bash
curl -s https://raw.githubusercontent.com/goodway/api-tracker/main/run.sh | bash -s "https://api.example.com/endpoint" 30 300 1500 5 1
```

### Parameters:

| Parameter           | Description                              |
|-------------------|------------------------------------------|
| `API_URL`         | URL of the API endpoint to monitor       |
| `total_time_minutes` | Duration in minutes to run monitoring   |
| `interval_seconds`  | Interval between checks (in seconds)    |
| `threshold_ms`     | Delay threshold (in milliseconds)       |
| `timeout_seconds`  | Optional timeout for requests (default: 5) |
| `analysis_mode`    | Optional analysis mode (0–2, default: 1) |

---

## 📊 Output

- **Console Logs**: Real-time updates with color-coded status messages.
- **Log Files**: Detailed logs saved in `logs/` directory with timestamps.

### Example Console Output:

```
📊 Progress: ██████████████████████████████████████████ 100% (1/1)
✅ API is available
⏱️  SLOW RESPONSE: Status: 200, Time: 1800ms
```

### Example Statistics:

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                     MONITORING STATISTICS                                    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Total checks: 100
║ Successful: 95 (95%)
║ Slow: 5 (5%)
║ Errors: 0 (0%)
║ HTTP errors: 0
║ Timeouts: 0
║ Minimum time: 120ms
║ Maximum time: 1800ms
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## 📁 Log Files

All logs are saved in the `logs/` directory with names like:

```
api_monitor_api.example.com_20250405_123456.log
```

---

## 🧪 Requirements

- Bash shell
- `curl` installed

---

## 🧑‍💻 Author

Maintained by Serge Goodway

---

## 📄 License

This project is licensed under the MIT License.

--- 

**Note**: This tool is designed for basic API monitoring and can be extended or customized as needed.