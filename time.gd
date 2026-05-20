extends Label

var time = 0
var seconds_per_day = 0.1
var year = 2026
var month = 0
var day = 0
var days_since_start = 0
var days_per_month = [31,29,31,30,31,30,31,31,30,31,30,31]
var is_leap_year=false
var paused = false

func _input(event):
	if event.is_action_pressed("escape"):
		paused = !paused

var time_accum = 0.0

func is_leap(y):
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)
	

func _process(delta):
	if paused:
		return
	
	time_accum += delta
	
	if time_accum >= seconds_per_day:
		time_accum = 0
		days_since_start += 1
		day += 1
		
		var dim = days_per_month[month]
		
		# February leap year adjustment
		if month == 1 and is_leap(year):
			dim = 29
		
		if day >= dim:
			day = 0
			month += 1
			
			if month >= 12:
				month = 0
				year += 1
		
		self.text = str(year) + " : " + str(month + 1) + " : " + str(day + 1)
