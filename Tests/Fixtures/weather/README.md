# Weather fixtures

Real responses recorded from the Open-Meteo forecast API on 2026-10-26 (data CC BY 4.0, https://open-meteo.com/):

- `open-meteo-bangkok-drizzle.json`: `?latitude=13.8&longitude=100.5&current=weather_code,is_day&timezone=auto` (WMO code 51, drizzle)
- `open-meteo-svalbard.json`: `?latitude=78.2&longitude=15.6&current=weather_code,is_day&timezone=auto` (WMO code 45, fog)
- `open-meteo-error.json`: an out-of-range latitude, the API's error shape

`WeatherTests.swift` parses these offline. No test touches the network.
