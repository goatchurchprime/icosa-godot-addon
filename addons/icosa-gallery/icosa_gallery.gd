@tool
## icosa browser.
extends Control

var current_page = 1
const DEFAULT_COLUMN_SIZE = 5
@export var api : IcosaGalleryAPI
@onready var thumbnail_scene := preload("res://addons/icosa-gallery/thumbnail.tscn")

var viewing_single_asset = false
var current_search : IcosaGalleryAPI.Search = IcosaGalleryAPI.create_default_search()
var chosen_thumbnail : Control
var asset_size = 250

signal model_downloaded(model_file)

func _ready():
	_on_search_bar_text_submitted("")
	
func _on_search_bar_text_submitted(new_text):
	api.fade_out(%Logo)
	current_search.keywords = new_text
	current_page = 1
	current_search.page_token = current_page
	if not chosen_thumbnail == null:
		_on_go_back_pressed()
	
	var url = api.build_query_url_from_search_object(current_search)
	#print(url)
	api.current_request = IcosaGalleryAPI.RequestType.SEARCH
	var error = api.request(url)
	if error != OK:
		push_error("An error occurred in the HTTP request.")

func _on_api_request_completed(result, response_code, headers, body):
	var json = JSON.new()
	json.parse(body.get_string_from_utf8())
	var response = json.get_data()
	#print(response)
	var total_assets
	if "totalSize" in response:
		total_assets = response["totalSize"]
	# Update asset found / not found labels
	if total_assets == 0:
		%Logo.show()
		%NoAssetsLabel.show()
		%AssetsFound.hide()
	else:
		%Logo.hide()
		%NoAssetsLabel.hide()
		%AssetsFound.show()
		if total_assets is int:
			print("assets!!!")
			%AssetsFound.text = "Total assets found: " + str(int(total_assets))
		else:
			print(result)
		# Create/update pagination buttons
		var total_pages = api.get_pages_from_total_assets(current_search.page_size, total_assets)
		_refresh_pagination_buttons(current_page, total_pages)
		# Optionally show/hide pagination controls based on total assets
	if total_assets > api.PAGE_SIZE_DEFAULT:
		%Pagination.show()
	else:
		%Pagination.hide()
	# Process assets if it's a search result
	if api.current_request == IcosaGalleryAPI.RequestType.SEARCH:
		var assets = api.get_asset_objects_from_response(response)
		# Clear previous assets
		for child in %AssetGrid.get_children():
			child.queue_free()
		# Create new asset thumbnails
		for asset in assets:
			var asset_thumbnail = thumbnail_scene.instantiate() as IcosaGalleryThumbnail
			asset_thumbnail.pressed.connect(select_asset.bind(asset_thumbnail))
			asset_thumbnail.display_name = asset.display_name
			asset_thumbnail.author_name = asset.author_name
			asset_thumbnail.description = asset.description
			asset_thumbnail.license = asset.license
			asset_thumbnail.thumbnail_url = asset.thumbnail
			%AssetGrid.add_child(asset_thumbnail)
			var format_index = 0
			for format_type in asset.formats:
				if format_type == "GLTF2":
					var svg_code = '<svg width="16" height="16"><circle cx="12" cy="6" r="12" fill="green"/></svg>'
					var image = Image.new()
					var icon = image.load_svg_from_string(svg_code, 1.0)
					asset_thumbnail.formats.get_popup().add_icon_item(image, format_type)
				else:
					asset_thumbnail.formats.get_popup().add_item(format_type, format_index)
				format_index += 1
			asset_thumbnail.formats.get_popup().id_pressed.connect(download_asset.bind(asset, asset_thumbnail))
			
		_on_asset_columns_value_changed(%AssetColumns.value)

func download_asset(index, asset : IcosaGalleryAPI.Asset, thumbnail : IcosaGalleryThumbnail):
	# Get the format type (e.g., "GLTF2", "OBJ", etc.)
	var format_type = asset.formats.keys()[index]
	
	# Create a sanitized asset name for the directory and file prefix
	# Convert to lowercase for consistent file naming
	var asset_name_sanitized = asset.display_name.validate_filename().to_lower()
	
	# Get the URLs for the selected format
	var download_queue = []
	for urls in asset.formats.values()[index]:
		download_queue.append(urls)
	
	# Show the progress bar before starting downloads
	
	# Create a single HTTPDownload instance for all files
	var download = IcosaDownload.new()

	
	add_child(download)
	var processed_queue = []
	for url in download_queue:
		url = url as String
		var address = url.split("https://")
		if address.size() > 2:
			url = "https://" + address[1] + address[2].uri_encode() ## format webarchive link
			processed_queue.append(url)
	#print(processed_queue)
	
	# Set the asset name for the download directory
	download.asset_name = asset_name_sanitized
	download.asset_id = asset.id
	download.url_queue = processed_queue
	
	# Connect signals for progress tracking
	download.files_downloaded.connect(thumbnail.update_progress)
	download.download_progress.connect(thumbnail.update_bytes_progress)
	download.download_queue_completed.connect(thumbnail._on_download_queue_completed)
	
	var id = download.asset_id.split("/")[1]
	### hmm.
	var model_file = download.root_directory + "icosa_downloads/" + download.asset_name + "_" + id + "/" + IcosaDownload.file_from_url(processed_queue[0])
	download.download_queue_completed.connect(func():
		emit_signal("model_downloaded", model_file)
	)
	
	
	download.host_offline.connect(show_host_offline_popup)
	# Start the download process
	download.start()



func select_asset(selected_thumbnail : Control):
	# Hide all other thumbnails and enlarge the selected one
	for thumbnail in selected_thumbnail.get_parent().get_children():
		thumbnail.hide()
	selected_thumbnail.show()
	selected_thumbnail.custom_minimum_size = Vector2(size.x/1.2, size.y/1.4)
	selected_thumbnail.disabled = true
	%AssetGrid.alignment = FlowContainer.AlignmentMode.ALIGNMENT_CENTER
	chosen_thumbnail = selected_thumbnail
	%GoBack.show()
	%Pagination.hide()
	viewing_single_asset = true

func _on_go_back_pressed():
	
	viewing_single_asset = false
	%GoBack.hide()
	%Pagination.show()
	chosen_thumbnail.disabled = false
	%AssetGrid.alignment = FlowContainer.AlignmentMode.ALIGNMENT_BEGIN
	for thumbnail in %AssetGrid.get_children():
		thumbnail.custom_minimum_size = Vector2(asset_size, asset_size)
		thumbnail.show()

func _on_resized():
	if viewing_single_asset:
		pass
	else:
		_on_asset_columns_value_changed(%AssetColumns.value)

func _on_asset_columns_value_changed(value):
	if viewing_single_asset: 
		pass
	else:
		var width = size.x
		var each = width / value - 10
		for asset in %AssetGrid.get_children():
			asset.custom_minimum_size = Vector2(each, each)
			asset.size = Vector2(each, each)

# Pagination Button Logic
func _refresh_pagination_buttons(current, total_pages):
	# Clear previous pagination buttons
	for child in %PageNumbers.get_children():
		child.queue_free()
	
	# Get the page labels to show (numbers or "...")
	var page_buttons = get_pagination_buttons(current, total_pages)
	for page_label in page_buttons:
		var page_button = Button.new()
		# If the label is a number, configure button to be clickable
		if typeof(page_label) == TYPE_INT:
			page_button.text = str(page_label)
			page_button.toggle_mode = true
			# Disable button if it's the current page
			page_button.disabled = (page_label == current)
			page_button.toggled.connect(on_page_number_pressed.bind(page_label, page_button))
		else:
			# If it's a string (i.e. "..."), show a disabled button
			page_button.text = "..."
			page_button.disabled = true
		
		%PageNumbers.add_child(page_button)
	


func get_pagination_buttons(current, total_pages):
	var pages = []
	
	if total_pages <= 6:
		# If there are 6 or fewer pages, show all pages
		for i in range(1, total_pages + 1):
			pages.append(i)
	else:
		# When there are more than 6 pages, dynamically choose which pages to show
		if current <= 3:
			# Show first four pages, ellipsis, and last page
			pages = [1, 2, 3, 4, "...", total_pages]
		elif current >= total_pages - 2:
			# Show first page, ellipsis, and last four pages
			pages = [1, "...", total_pages - 3, total_pages - 2, total_pages - 1, total_pages]
		else:
			# Show first page, ellipsis, current -1, current, current +1, ellipsis, and last page
			pages = [1, "...", current - 1, current, current + 1, "...", total_pages]
			
	return pages

func on_page_number_pressed(toggled, page_number, page_button):
	current_page = page_number
	current_search.page_token = page_number
	
	# Refresh pagination buttons so the current page is highlighted
	var total_pages = api.get_pages_from_total_assets(current_search.page_size, api.total_size)
	_refresh_pagination_buttons(current_page, total_pages)
	
	request_new_page()

func _on_previous_page_pressed():
	if current_page > 1:
		current_page -= 1
		current_search.page_token = current_page
		request_new_page()

func _on_next_page_pressed():
	var total_pages = api.get_pages_from_total_assets(current_search.page_size, api.total_size)
	if current_page < total_pages:
		current_page += 1
		current_search.page_token = current_page
		request_new_page()

func request_new_page():
	var url = api.build_query_url_from_search_object(current_search)
	api.current_request = IcosaGalleryAPI.RequestType.SEARCH
	var error = api.request(url)
	if error != OK:
		push_error("Failed to load new page.")


func show_host_offline_popup():
	%HostOffline.show()

## Help menu, also about.
func _on_help_pressed():
	%Help.show()

func _on_search_options_toggled(toggled_on):
	if toggled_on:
		#%BottomBar.size_flags_vertical = SIZE_EXPAND_FILL
		%SearchOptionsMenu.show()
	else:
		#%BottomBar.size_flags_vertical = SIZE_SHRINK_END
		%SearchOptionsMenu.hide()


##### search gui options.

func _on_search_author_text_changed(new_text):
	current_search.author_name = new_text


func _on_search_description_text_changed(new_text):
	current_search.description = new_text


func _on_gltf_2_toggled(toggled_on):
	if toggled_on:
		current_search.formats.append("GLTF2")
		current_search.formats.erase("-GLTF2")
	else:
		current_search.formats.append("-GLTF2")
		current_search.formats.erase("GLTF2")
		

func _on_obj_toggled(toggled_on):
	if toggled_on:
		current_search.formats.append("OBJ")
		current_search.formats.erase("-OBJ")
	else:
		current_search.formats.append("-OBJ")
		current_search.formats.erase("OBJ")


func _on_fbx_toggled(toggled_on):
	if toggled_on:
		current_search.formats.append("FBX")
		current_search.formats.erase("-FBX")
	else:
		current_search.formats.append("-FBX")
		current_search.formats.erase("FBX")

## other model formats. no support for these yet. (TILT, BLOCKS, etc)
func _on_other_toggled(toggled_on):
	pass # Replace with function body.


func _on_remixable_toggled(toggled_on):
	current_search.license.append("REMIXABLE")

## non derivative works are off by default. not really the idea here.
func _on_nd_toggled(toggled_on):
	current_search.license.append("ALL_CC")



func _on_min_triangles_value_changed(value):
	current_search.triangle_count_min = value


func _on_max_triangles_value_changed(value):
	current_search.triangle_count_max = value


## the array `IcosaGalleryAPI.order_by` handles ordering. will make GUI later. 
func _on_best_toggled(toggled_on):
	#current_search. ?? no api for this yet.
	pass 
	refresh_search()

func _on_curated_toggled(toggled_on):
	current_search.curated = toggled_on
	refresh_search()

func _on_page_size_value_changed(value):
	current_search.page_size = value


func _on_search_author_text_submitted(new_text):
	refresh_search()

func _on_search_description_text_submitted(new_text):
	refresh_search()


func refresh_search():
	_on_search_bar_text_submitted(current_search.keywords)


## FIXME, do this more gracefully.
func _on_order_pressed():
	if %ORDER.item_count < 1:
		for ordering in IcosaGalleryAPI.order_by:
			%ORDER.add_item(ordering)

func _on_order_item_selected(index):
	current_search.order.append(%ORDER.get_item_text(index))


func _on_focus_entered():
	pass # Replace with function body.
