pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

// Serviço central de previsão do tempo e clima (Open/wttr.in).
// Detecção automática por IP no primeiro uso, com override de cidade
// configurável pelo usuário em ~/.config/hollow-wired/weather.json.
QtObject {
    id: root

    property string city: ""
    property bool ready: false
    property bool loading: false

    // Dados do clima
    property string temp: "--"
    property string desc: "..."
    property string place: ""
    property int code: 0
    property string feels: ""
    property string humidity: ""
    property string wind: ""
    property string sunrise: ""
    property string sunset: ""
    property var days: []
    property string icon: Theme.icons.cloudy

    property FileView configFile: FileView {
        id: configFile
        path: Quickshell.env("HOME") + "/.config/hollow-wired/weather.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const t = text().trim();
                if (t) {
                    const parsed = JSON.parse(t);
                    if (typeof parsed.city === "string") {
                        root.city = parsed.city;
                    }
                }
            } catch (e) {
                console.log("WeatherService: erro ao ler weather.json:", e);
            } finally {
                root.ready = true;
                root.refresh();
            }
        }
        onLoadFailed: {
            root.ready = true;
            root.city = "";
            root.saveConfig();
            root.refresh();
        }
    }

    function saveConfig() {
        if (!root.ready) return;
        try {
            configFile.setText(JSON.stringify({ city: root.city }, null, 2) + "\n");
        } catch (e) {
            console.log("WeatherService: erro ao salvar weather.json:", e);
        }
    }

    function setCity(newCity) {
        root.city = (newCity || "").trim();
        root.saveConfig();
        root.refresh();
    }

    // Atualização periódica a cada 20 minutos
    property Timer pollTimer: Timer {
        interval: 20 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    function refresh() {
        if (weatherProc.running) return;
        root.loading = true;
        const loc = encodeURIComponent(root.city.replace(/\s+/g, "+"));
        weatherProc.command = ["curl", "-sf", "--max-time", "12", "http://wttr.in/" + loc + "?format=j1&lang=pt"];
        weatherProc.running = true;
    }

    property Process weatherProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const data = JSON.parse(text);
                    if (!data || !data.current_condition || data.current_condition.length === 0) return;
                    const cur = data.current_condition[0];
                    root.temp = (cur.temp_C || "--") + "°C";
                    root.code = parseInt(cur.weatherCode || "113");
                    root.desc = (cur.lang_pt && cur.lang_pt[0]) ? cur.lang_pt[0].value : (cur.weatherDesc ? cur.weatherDesc[0].value : "");
                    root.place = (data.nearest_area && data.nearest_area[0] && data.nearest_area[0].areaName) ? data.nearest_area[0].areaName[0].value : root.city;

                    root.feels = cur.FeelsLikeC ? cur.FeelsLikeC + "°" : "";
                    root.humidity = cur.humidity ? cur.humidity + "%" : "";
                    root.wind = cur.windspeedKmph ? cur.windspeedKmph + " km/h" : "";

                    const astro = (data.weather && data.weather[0] && data.weather[0].astronomy) ? data.weather[0].astronomy[0] : null;
                    root.sunrise = astro ? root.to24h(astro.sunrise) : "";
                    root.sunset = astro ? root.to24h(astro.sunset) : "";

                    const hour = new Date().getHours();
                    root.icon = root.iconFor(root.code, hour);

                    const dList = [];
                    const names = Theme.locale === "en" ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
                    for (let i = 0; i < (data.weather || []).length && i < 3; i++) {
                        const w = data.weather[i];
                        const d = new Date(w.date + "T12:00:00");
                        dList.push({
                            label: i === 0 ? Theme.t("dash.today", "Hoje") : names[d.getDay()],
                            min: w.mintempC + "°",
                            max: w.maxtempC + "°",
                            code: parseInt((w.hourly && w.hourly[4]) ? w.hourly[4].weatherCode : "113")
                        });
                    }
                    root.days = dList;
                } catch (e) {
                    console.log("WeatherService: resposta inválida:", e);
                }
            }
        }
    }

    function to24h(text) {
        const m = /^(\d{1,2}):(\d{2})\s*(AM|PM)?$/i.exec((text || "").trim());
        if (!m) return text || "";
        let h = parseInt(m[1]);
        const ampm = (m[3] || "").toUpperCase();
        if (ampm === "PM" && h !== 12) h += 12;
        if (ampm === "AM" && h === 12) h = 0;
        return ("0" + h).slice(-2) + ":" + m[2];
    }

    function iconFor(code, hour) {
        const night = hour < 6 || hour >= 18;
        if (code === 113) return night ? Theme.icons.night : Theme.icons.sunny;
        if (code === 116) return Theme.icons.partly;
        if (code === 119 || code === 122) return Theme.icons.cloudy;
        if ([143, 248, 260].includes(code)) return Theme.icons.fog;
        if ([200, 386, 389, 392, 395].includes(code)) return Theme.icons.lightning;
        if ([299, 302, 305, 308, 356, 359].includes(code)) return Theme.icons.pouring;
        if ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].includes(code))
            return Theme.icons.snowy;
        if (code >= 176) return Theme.icons.rainy;
        return Theme.icons.cloudy;
    }
}
