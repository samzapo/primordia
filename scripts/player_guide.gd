extends RefCounted
static var _data: Dictionary={}
static func data() -> Dictionary:
	if _data.is_empty():_data=JSON.parse_string(FileAccess.get_file_as_string("res://data/player_guide.json"))
	return _data
static func safe(text: String) -> String:return text.replace("[","[lb]")
static func entries(items: Array,science: bool=false) -> String:
	var text:=""
	for item in items:
		text+="[b]"+safe(item.title)+"[/b]\n"+safe(item.text)+"\n"
		if science:
			for source in item.sources:text+="[color=#80efce][url="+source.url+"]"+safe(source.title)+" ↗[/url][/color]\n"
		text+="\n"
	return text
static func gameplay(touch: bool) -> String:
	var guide: Dictionary=data().gameplay
	return "[b]Your controls[/b]\n\n"+entries(guide.touch if touch else guide.desktop)+"[b]Shape your cell[/b]\n\n"+entries(guide.common)
static func mechanics(section: int=-1) -> String:
	var text:="These are simple game rules inspired by living cells. Links explain the real science; they do not validate the game’s recipes, rates or costs.\n\n"
	for i in data().mechanics.size():
		if section>=0 and i!=section:continue
		var group: Dictionary=data().mechanics[i]
		text+="[b]"+safe(group.title)+"[/b]\n\n"+entries(group.items,true)
	return text
static func allowed_url(value) -> bool:
	if not value is String or not value.begins_with("https://"):return false
	for group in data().mechanics:
		for item in group.items:
			for source in item.sources:
				if source.url==value:return true
	return false
