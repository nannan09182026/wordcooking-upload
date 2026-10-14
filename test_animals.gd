extends "res://test_cooking.gd"

func meal(animal):
	game.barn.current = animal.data["type"]
	game.barn.feed += 1
	game.barn.place_feed(animal.position)
	game.barn.eat(animal, game.barn.foods.back())

func run():
	if not "--test-mode" in OS.get_cmdline_user_args():
		quit(1)
		return
	seed(42)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.money = 2000
	game.barn.set_process(false)
	game.farm.set_process(false)
	game.dining.set_process(false)
	var barn = game.barn
	check(barn.animal_sounds.size() == 7, "six stage voices and one growth sound loaded")
	for stream in barn.animal_sounds.values():
		check(stream != null and stream.get_length() > 0.4, "animal sound decodes")
	game.show_page("畜棚")
	for species in barn.TYPES:
		barn.build_home(species)
		barn.enter_pen(species)
		check(not barn.animal_player.playing, "empty pen has no voice: " + species)
		barn.buy_animal()
		var animal = barn.animals.back()
		barn.leave_pen()
		var count = barn.voice_count
		barn.enter_pen(species)
		check(barn.voice_count == count + 1 and barn.last_voice.ends_with("_baby"), "entry plays baby voice once: " + species)
		check(animal.data["sway"] > 0, "entry voice triggers own card animation: " + species)
		barn.advance(0.04)
		check(absf(animal.rotation) > 0, "call visibly sways card: " + species)
		count = barn.voice_count
		barn.enter_pen(species)
		check(barn.voice_count == count, "same pen does not retrigger entry: " + species)
		game.show_page("后厨")
		check(not barn.animal_player.playing and animal.rotation == 0, "switch page stops voice and sway: " + species)
		meal(animal)
		meal(animal)
		check(animal.data["growth"] == 2 and barn.voice_count == count, "offscreen growth is silent: " + species)
		game.show_page("畜棚")
		check(barn.last_voice == barn.VOICES[species] + "_adult" and barn.voice_count == count + 1, "return gives adult greeting not delayed growth: " + species)
		# 第二只在当前页面成长，成长声音仅触发一次。
		barn.buy_animal()
		var baby = barn.animals.back()
		count = barn.voice_count
		meal(baby)
		check(barn.voice_count == count, "first meal does not play adult cue: " + species)
		meal(baby)
		check(barn.last_voice == "grown" and barn.voice_count == count + 1 and baby.data["sway"] > 0, "visible adulthood cues once: " + species)
		meal(baby)
		check(barn.voice_count == count + 1, "adult meals never repeat growth cue: " + species)
		# 走到指定目标、停留、随机挑选下一处，检验三种动物。
		animal.data["rest"] = 0
		animal.data["wait"] = 0
		animal.data["base"] = Vector2(430, 340)
		animal.data["target"] = Vector2(650, 340)
		barn.advance(1.0)
		check(animal.position.x > 440 and animal.position.x < 500, "idle actually walks across pen: " + species)
		animal.data["wait"] = 2.0
		animal.data["sway"] = 0
		var point = animal.position
		barn.advance(0.2)
		check(animal.position == point and animal.rotation == 0, "resting animal no longer bounces: " + species)
		barn.choose_walk_target(animal)
		check(animal.data["target"].distance_to(animal.data["base"]) >= 55, "random walking target is meaningful: " + species)
		animal.position = Vector2(1600, 800)
		barn.drop_animal(animal)
		check(barn.PEN_AREA.encloses(Rect2(animal.position, animal.size)), "drag release clamps animal inside pen: " + species)
		point = animal.position
		animal.pressed = true
		barn.advance(2)
		check(animal.position == point, "user dragging overrides wandering: " + species)
		animal.pressed = false
		animal.expanded = true
		barn.advance(2)
		check(animal.position == point, "detail inspection holds animal still: " + species)
		animal.expanded = false
		barn.leave_pen()
		check(not barn.animal_player.playing, "return to home stops animal sound: " + species)
	# 同在畜棚但看别的动物，也不能发声或播成长提示。
	barn.enter_pen("猪")
	var chicken = barn.animals[0]
	var before = barn.voice_count
	check(not barn.speak(chicken, true) and barn.voice_count == before, "other pen cannot trigger growth sound")
	var pig = barn.animals.back()
	game.feedback.toggle_mute()
	check(not barn.animal_player.playing and not barn.speak(pig), "mute immediately stops and blocks animal voice")
	game.feedback.toggle_mute()
	game.feedback.set_volume(0)
	check(not barn.speak(pig, false, true), "zero volume blocks voice and gesture")
	game.feedback.set_volume(0.4)
	game.feedback.reduced_motion = true
	check(barn.speak(pig, false, true) and pig.data["sway"] == 0, "reduced motion keeps voice without sway")
	game.feedback.reduced_motion = false
	barn.silence_animals()
	barn.voice_gap = 0
	check(barn.speak(pig) and not barn.speak(pig), "idle chorus limited to one voice with cooldown")
	before = barn.voice_count
	game.show_page("农场")
	for i in range(150):
		barn.advance(0.1)
	check(barn.voice_count == before, "hidden idle never schedules audible calls")
	game.show_page("畜棚")
	barn.silence_animals()
	barn.voice_gap = 0
	pig.data["call_wait"] = 0
	barn.advance(0.1)
	check(barn.voice_count == before + 2, "visible idle animal calls at its interval")
	# 饲料放到边缘也能吃到，而不是一直追一个到不了的位置。
	barn.enter_pen("鸡")
	barn.buy_animal()
	var hungry = barn.animals.back()
	hungry.data["base"] = Vector2(400, 300)
	for a in barn.animals:
		if a != hungry:
			a.pressed = true
	barn.feed += 1
	barn.place_feed(Vector2(1160, 550))
	for i in range(160):
		barn.advance(0.1)
	check(hungry.data["growth"] == 1 and barn.foods.is_empty(), "hungry animal prioritizes and reaches edge feed")
	for a in barn.animals:
		a.pressed = false
		check(barn.PEN_AREA.encloses(Rect2(a.data["base"], a.size)), "wandering bounds retained")
	game.feedback.toast.hide()
	await snapshot("animal-walking-preview")
	print("ANIMAL CHECKS: ", checks, " checks, ", failures, " failures")
	game.queue_free()
	await process_frame
	await process_frame
	quit(failures)
