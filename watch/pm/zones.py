"""Deliberately coarse PM itinerary time zones; unknown places stay unknown."""


PROVINCES = {
    'Ontario': 'America/Toronto', 'Quebec': 'America/Toronto',
    'Manitoba': 'America/Winnipeg', 'Saskatchewan': 'America/Regina',
    'Alberta': 'America/Edmonton', 'British Columbia': 'America/Vancouver',
    'Nova Scotia': 'America/Halifax', 'New Brunswick': 'America/Halifax',
    'Prince Edward Island': 'America/Halifax', 'PEI': 'America/Halifax',
    'Newfoundland and Labrador': 'America/St_Johns', 'Yukon': 'America/Whitehorse',
    'Northwest Territories': 'America/Yellowknife', 'NWT': 'America/Yellowknife',
    'Nunavut': 'America/Iqaluit',
}
OVERRIDES = {
    'Saint-Pierre-et-Miquelon, France': 'America/Miquelon',
    'National Capital Region, Canada': 'America/Toronto',
    'Greater Toronto Area, Ontario': 'America/Toronto',
    'Washington, D.C., United States of America': 'America/New_York',
    'New York City, United States of America': 'America/New_York',
}
COUNTRIES = {
    'France': 'Europe/Paris', 'United Kingdom': 'Europe/London', 'Belgium': 'Europe/Brussels',
    'Germany': 'Europe/Berlin', 'Italy': 'Europe/Rome', 'Japan': 'Asia/Tokyo',
    'Mexico': 'America/Mexico_City', 'Ukraine': 'Europe/Kyiv', 'Poland': 'Europe/Warsaw',
    'Netherlands': 'Europe/Amsterdam', 'Switzerland': 'Europe/Zurich', 'Norway': 'Europe/Oslo',
    'Sweden': 'Europe/Stockholm', 'Finland': 'Europe/Helsinki', 'Denmark': 'Europe/Copenhagen',
    'Spain': 'Europe/Madrid', 'Portugal': 'Europe/Lisbon', 'Ireland': 'Europe/Dublin',
    'Israel': 'Asia/Jerusalem', 'India': 'Asia/Kolkata', 'China': 'Asia/Shanghai',
    'South Korea': 'Asia/Seoul', 'Antigua and Barbuda': 'America/Antigua',
    'Guyana': 'America/Guyana', 'South Africa': 'Africa/Johannesburg', 'Egypt': 'Africa/Cairo',
    'Saudi Arabia': 'Asia/Riyadh', 'United Arab Emirates': 'Asia/Dubai', 'Qatar': 'Asia/Qatar',
    'Türkiye': 'Europe/Istanbul', 'Turkey': 'Europe/Istanbul', 'Singapore': 'Asia/Singapore',
    'Philippines': 'Asia/Manila', 'Indonesia': 'Asia/Jakarta', 'Vietnam': 'Asia/Ho_Chi_Minh',
    'Malaysia': 'Asia/Kuala_Lumpur', 'Peru': 'America/Lima', 'Chile': 'America/Santiago',
    'Brazil': 'America/Sao_Paulo', 'Argentina': 'America/Argentina/Buenos_Aires',
}


def zone_for(heading: str, lat: float | None, lon: float | None) -> str | None:
    heading = ' '.join(heading.split())
    if heading in OVERRIDES:
        return OVERRIDES[heading]
    region = heading.rsplit(',', 1)[-1].strip()
    if region in PROVINCES:
        return PROVINCES[region]
    if region == 'United States of America' and lon is not None:
        for boundary, zone in ((-87, 'America/New_York'), (-101, 'America/Chicago'),
                               (-115, 'America/Denver')):
            if lon >= boundary:
                return zone
        return 'America/Los_Angeles'
    return COUNTRIES.get(region)
