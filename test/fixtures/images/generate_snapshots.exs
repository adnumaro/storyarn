# Generates reference snapshots for ZoneImageExtractor snapshot tests.
#
# Run with: mix run test/fixtures/images/generate_snapshots.exs
#
# This uses the same crop/resize/sharpen pipeline as ZoneImageExtractor
# but without DB/storage (direct image operations). Output is saved to
# test/fixtures/images/snapshots/ and committed to the repo.
#
# Regenerate when: libvips version changes, Image library upgrades,
# or extract pipeline parameters change (@min_output_size, sigma, etc.)
#
# Note: ZoneImageExtractor always crops via bounding_box/1 (rectangular),
# so all zones use simple 4-vertex rectangles matching the crop region.

output_dir = "test/fixtures/images/snapshots"
File.rm_rf!(output_dir)
File.mkdir_p!(output_dir)

{:ok, img} = Image.open("test/fixtures/images/fantasy_map.jpg")
img_w = Image.width(img)
img_h = Image.height(img)

min_output_size = 1000

rect = fn x1, y1, x2, y2 ->
  [
    %{"x" => x1, "y" => y1},
    %{"x" => x2, "y" => y1},
    %{"x" => x2, "y" => y2},
    %{"x" => x1, "y" => y2}
  ]
end

zones = [
  {"strait_island", rect.(49.0, 36.0, 57.0, 44.0)},
  {"northwest_peninsula", rect.(5.0, 6.0, 33.0, 38.0)},
  {"sw_island", rect.(4.0, 81.0, 16.0, 93.0)},
  {"waterfall_cove", rect.(74.0, 22.0, 92.0, 38.0)},
  {"south_forest", rect.(14.0, 53.0, 58.0, 82.0)},
  {"panoramic_strait", rect.(0.0, 28.0, 100.0, 48.0)},
  {"river_valley", rect.(20.0, 40.0, 42.0, 68.0)},
  {"tiny_detail", rect.(44.0, 64.0, 50.0, 70.0)}
]

alias Storyarn.Scenes.ZoneImageExtractor

IO.puts("Generating snapshots for #{length(zones)} zones...\n")

for {name, vertices} <- zones do
  {min_x, min_y, max_x, max_y} = ZoneImageExtractor.bounding_box(vertices)

  left = round(min_x / 100.0 * img_w)
  top = round(min_y / 100.0 * img_h)
  crop_w = max(1, round((max_x - min_x) / 100.0 * img_w))
  crop_h = max(1, round((max_y - min_y) / 100.0 * img_h))

  left = max(0, min(left, img_w - 1))
  top = max(0, min(top, img_h - 1))
  crop_w = min(crop_w, img_w - left)
  crop_h = min(crop_h, img_h - top)

  {:ok, cropped} = Image.crop(img, left, top, crop_w, crop_h)

  larger = max(Image.width(cropped), Image.height(cropped))

  final =
    if larger < min_output_size do
      scale = min_output_size / larger
      {:ok, resized} = Image.resize(cropped, scale)
      resized
    else
      cropped
    end

  {:ok, sharpened} = Image.sharpen(final, sigma: 1.5)

  out_path = Path.join(output_dir, "#{name}.webp")
  Image.write!(sharpened, out_path)

  w = Image.width(sharpened)
  h = Image.height(sharpened)
  hash = :crypto.hash(:sha256, File.read!(out_path)) |> Base.encode16(case: :lower)
  IO.puts("  #{name}: #{w}x#{h} sha256=#{String.slice(hash, 0, 16)}...")
end

IO.puts("\nSnapshots saved to #{output_dir}/")
IO.puts("Commit these files to the repo.")
