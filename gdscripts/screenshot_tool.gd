@tool
extends Node

func _ready():
    await get_tree().process_frame
    await get_tree().process_frame
    var viewport = get_viewport()
    if viewport:
        var img = viewport.get_texture().get_image()
        if img:
            img.save_png("/tmp/game_screenshot.png")
            print("Screenshot saved")
    get_tree().quit()
