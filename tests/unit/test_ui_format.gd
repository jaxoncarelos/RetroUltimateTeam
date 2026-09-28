extends GutTest
## Number and name formatting for the pixel UI: CoinPill.fmt (compact millions, so a
## 5,000,000 balance fits the pill) and PixelFont.fit (condensed face for long names).


func test_coin_format() -> void:
	assert_eq(CoinPill.fmt(0), "0")
	assert_eq(CoinPill.fmt(750), "750")
	assert_eq(CoinPill.fmt(12450), "12,450")
	assert_eq(CoinPill.fmt(999999), "999,999")
	assert_eq(CoinPill.fmt(1000000), "1M")
	assert_eq(CoinPill.fmt(1250000), "1.25M")
	assert_eq(CoinPill.fmt(1999999), "1.99M", "never rounds up")
	assert_eq(CoinPill.fmt(1500000), "1.5M")
	assert_eq(CoinPill.fmt(5000000), "5M")
	assert_eq(CoinPill.fmt(123456789), "123M")
	assert_eq(CoinPill.fmt(2500000000), "2.5B")
	assert_eq(CoinPill.fmt(-1250), "-1,250")
	assert_eq(CoinPill.fmt_full(5000000), "5,000,000")


func test_coin_pill_sizes_to_content() -> void:
	var small := CoinPill.new(0)
	var big := CoinPill.new(999999)
	autofree(small)
	autofree(big)
	assert_gt(big.custom_minimum_size.x, small.custom_minimum_size.x)
	var text_w := PixelFont.text_width(CoinPill.fmt(999999))
	assert_gte(big.custom_minimum_size.x, float(text_w + 10), "text + coin fit inside")
	big.set_coins(5000000, false)
	assert_lt(big.custom_minimum_size.x, 70.0, "5M stays compact")


func test_name_fit() -> void:
	var short := PixelFont.fit("KELCE", 50)
	assert_false(short["condensed"])
	var long := PixelFont.fit("WASHINGTON", 50)
	assert_true(long["condensed"])
	assert_eq(long["text"], "WASHINGTON", "condensed face fits it whole")
	assert_lte(int(long["width"]), 50)
	var huge := PixelFont.fit("CROSKEY-MERRITT", 50)
	assert_true((huge["text"] as String).ends_with("."))
	assert_lte(int(huge["width"]), 50)
