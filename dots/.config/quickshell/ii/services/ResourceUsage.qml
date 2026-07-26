pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats
    property real cpuTemperature: 0 // °C, from k10temp (Tctl)
    property real gpuTemperature: 0 // °C, NVIDIA dGPU via nvidia-smi

    // Top load contributor, surfaced in the Temps hover popup. Polled only while
    // `topProcessPolling` is set (the popup toggles it on hover) since it spawns top.
    property bool topProcessPolling: false
    property string topCpuProcess: ""
    property real topCpuPercentage: 0  // raw top-style %CPU (can exceed 100 on multi-core hogs)
    property string topGpuProcess: ""
    property real topGpuUtilization: 0 // % GPU SM utilization, from nvidia-smi pmon

    // Network throughput, summed across all non-loopback interfaces (bytes/s).
    property real netDownSpeed: 0
    property real netUpSpeed: 0
    property var previousNetStats // { rx, tx, time }
    // Cumulative bytes transferred today (sum of observed positive deltas, so a
    // counter reset on reboot/iface-down doesn't corrupt the tally). Reset at
    // midnight when the calendar day changes.
    property real netDownTotal: 0
    property real netUpTotal: 0
    property string netTotalDay: ""

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true 
        repeat: true
		onTriggered: {
            // Reload files
            fileMeminfo.reload()
            fileStat.reload()
            fileNetdev.reload()

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // Parse CPU usage
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3]

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            // Parse network throughput. /proc/net/dev columns: iface: rxBytes ...
            // (col 0) ... txBytes (col 8). Loopback is excluded.
            const textNetdev = fileNetdev.text()
            let rxTotal = 0, txTotal = 0
            for (const line of textNetdev.split("\n")) {
                const m = line.match(/^\s*([^:]+):\s*(.*)$/)
                if (!m || m[1].trim() === "lo") continue
                const nums = m[2].trim().split(/\s+/).map(Number)
                rxTotal += nums[0] || 0
                txTotal += nums[8] || 0
            }
            const now = Date.now()
            if (previousNetStats) {
                const dt = (now - previousNetStats.time) / 1000
                const downDelta = Math.max(0, rxTotal - previousNetStats.rx)
                const upDelta = Math.max(0, txTotal - previousNetStats.tx)
                if (dt > 0) {
                    netDownSpeed = downDelta / dt
                    netUpSpeed = upDelta / dt
                }
                const today = new Date().toDateString()
                if (netTotalDay !== today) {
                    netDownTotal = 0
                    netUpTotal = 0
                    netTotalDay = today
                }
                netDownTotal += downDelta
                netUpTotal += upDelta
            }
            previousNetStats = { rx: rxTotal, tx: txTotal, time: now }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileNetdev; path: "/proc/net/dev" }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    // Poll CPU & GPU temperatures. hwmon numbers can shuffle across reboots,
    // so the CPU chip is resolved by name (k10temp) rather than a fixed path.
    Timer {
        interval: Config.options?.resources?.updateInterval ?? 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: temperatureProc.running = true
    }

    Process {
        id: temperatureProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "cpu=0; for h in /sys/class/hwmon/*; do if [ \"$(cat \"$h/name\" 2>/dev/null)\" = k10temp ]; then cpu=$(cat \"$h/temp1_input\" 2>/dev/null); break; fi; done; gpu=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' '); echo \"${cpu:-0} ${gpu:-0}\""]
        stdout: StdioCollector {
            id: temperatureCollector
            onStreamFinished: {
                const parts = temperatureCollector.text.trim().split(/\s+/)
                root.cpuTemperature = (Number(parts[0]) || 0) / 1000
                root.gpuTemperature = Number(parts[1]) || 0
            }
        }
    }

    Timer {
        running: root.topProcessPolling
        interval: Config.options?.resources?.updateInterval ?? 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: topProcessProc.running = true
    }

    // top's 2nd frame gives instantaneous %CPU (1st is since-boot); we skip top
    // itself. GPU line stays empty when nvidia-smi pmon reports no active SM use.
    Process {
        id: topProcessProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "c=$(top -bn2 -d 0.3 -w 512 | awk '/^ *PID +USER/{b++;next} b==2 && NF>=12 && $12!=\"top\" {print $12\"|\"$9; exit}'); echo \"CPU|${c:-|}\"; g=$(nvidia-smi pmon -c 1 2>/dev/null | awk 'NF>=8 && $1 !~ /^#/ {s=$4+0; if(s>m){m=s; nm=$NF}} END{if(nm!=\"\") print nm\"|\"m}'); echo \"GPU|${g:-|}\""]
        stdout: StdioCollector {
            id: topProcessCollector
            onStreamFinished: {
                let cpuName = "", cpuPct = 0, gpuName = "", gpuPct = 0
                for (const line of topProcessCollector.text.trim().split("\n")) {
                    const p = line.split("|")
                    if (p[0] === "CPU") { cpuName = p[1] || ""; cpuPct = Number(p[2]) || 0 }
                    else if (p[0] === "GPU") { gpuName = p[1] || ""; gpuPct = Number(p[2]) || 0 }
                }
                root.topCpuProcess = cpuName
                root.topCpuPercentage = cpuPct
                root.topGpuProcess = gpuName
                root.topGpuUtilization = gpuPct
            }
        }
    }
}
