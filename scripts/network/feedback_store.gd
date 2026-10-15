extends RefCounted
## Private durable inbox, independent of rotating pond checkpoints.
var directory := ""
func submit(report: Dictionary, author: String, context: Dictionary) -> Dictionary:
	var id=report.get("id","")
	var result: Dictionary={"kind":"feedback_result","id":id if id is String else "","ok":false}
	var pattern:=RegEx.new();pattern.compile("^[a-f0-9]{32}$")
	if not id is String or pattern.search(id)==null or author=="":
		result.message="Invalid report identity.";return result
	var category=report.get("category","")
	var title=report.get("title","")
	var description=report.get("description","")
	if not category is String or category not in ["bug","feature"] or not title is String or not description is String:
		result.message="Choose a bug report or feature request and enter text.";return result
	title=title.strip_edges();description=description.strip_edges()
	if title=="" or description=="" or title.length()>120 or description.length()>6000:
		result.message="Enter a title (up to 120 characters) and details (up to 6000).";return result
	var content: Dictionary={"category":category,"title":title,"description":description}
	var path: String=directory.path_join(id+".json")
	if FileAccess.file_exists(path):
		var previous=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not previous is Dictionary or previous.get("author","")!=author or previous.get("content",{})!=content:
			result.message="This report ID is already in use. Edit the draft and try again.";return result
		var sync_output: Array=[]
		if OS.execute("python3",[ProjectSettings.globalize_path("res://tools/durable_feedback.py"),"--sync",path],sync_output,true)!=0:
			result.message="Cannot confirm the save. Retry keeps the same report ID.";return result
		result.ok=true;result.message="Report saved. Thank you!";return result
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		result.message="Cannot save feedback right now. Your draft is still available.";return result
	var folder:=DirAccess.open(directory);var count:=0
	if folder==null:
		result.message="Cannot open feedback right now. Your draft is kept.";return result
	for name in folder.get_files():
		if name.ends_with(".json"):count+=1
	if count>=5000:
		result.message="The feedback inbox is full. Please try again later.";return result
	var temporary: String=path+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:
		result.message="Cannot save feedback right now. Your draft is still available.";return result
	file.store_string(JSON.stringify({"version":1,"id":id,"author":author,"created_unix":Time.get_unix_time_from_system(),"content":content,"context":context}))
	file.flush();file.close()
	var output: Array=[]
	var status:=OS.execute("python3",[ProjectSettings.globalize_path("res://tools/durable_feedback.py"),temporary,path],output,true)
	if status!=0:
		result.message="Cannot confirm the save. Retry keeps the same report ID.";return result
	result.ok=true;result.message="Report saved. Thank you!"
	return result
