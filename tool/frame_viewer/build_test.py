"""逐格錄影頁的資料：淺色、深色各留一份量測。

    python tool/frame_viewer/build_test.py

只用標準函式庫：量像素要 numpy、做拼圖要 ffmpeg，這裡換掉量像素那一步，測的是
掃錄影資料夾、把每一段放進頁面資料的組合。
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build


def write_recording(root, name, phases, costs, **extra):
    """一段錄影的 meta.json；頁面資料只讀這個檔。"""
    path = os.path.join(root, name)
    os.makedirs(path)
    meta = {'width': 30, 'height': 60, 'phases': phases, 'costs': costs, **extra}
    with open(os.path.join(path, 'meta.json'), 'w', encoding='utf-8') as f:
        json.dump(meta, f)
    return path


def rows_of(src, meta, spots):
    """換掉量像素：每一格的內容就是那一段的主執行緒時間。"""
    return [[cost] for cost in meta['costs']]


class CollectTest(unittest.TestCase):
    def setUp(self):
        self.config = {'designs': [{'key': 'candidate'}]}

    def test_淺色與深色各自保留自己的量測(self):
        with tempfile.TemporaryDirectory() as root:
            write_recording(root, 'candidate-light', ['長出'] * 3, [0.4, 4.5, 0.2],
                            moving=[True, True, False], gcNew=[0, 1.2, 0])
            write_recording(root, 'candidate-dark', ['呼吸'] * 5, [1, 2, 3, 4, 5],
                            moving=[True, True, True, False, False])

            data = build.collect(build.scan(self.config, root), None, rows_of)

            self.assertEqual(sorted(data['candidate']), ['dark', 'light'])
            light = data['candidate']['light']
            dark = data['candidate']['dark']
            self.assertIsNot(light, dark)
            self.assertEqual((light['n'], dark['n']), (3, 5))
            self.assertEqual(light['phases'], ['長出'] * 3)
            self.assertEqual(dark['phases'], ['呼吸'] * 5)
            self.assertEqual(light['costs'], [0.4, 4.5, 0.2])
            self.assertEqual(dark['costs'], [1, 2, 3, 4, 5])
            self.assertEqual((light['moving'], dark['moving']),
                             ([True, True, False], [True, True, True, False, False]))
            self.assertEqual(light['gcNew'], [0, 1.2, 0])
            self.assertEqual(dark['gcNew'], [])
            self.assertEqual(light['frames'], [[0.4], [4.5], [0.2]])
            self.assertEqual(dark['frames'], [[1], [2], [3], [4], [5]])

    def test_量測照幀數截掉多出來的部分(self):
        with tempfile.TemporaryDirectory() as root:
            write_recording(root, 'candidate-light', ['長出'] * 3, [0.4, 4.5, 0.2],
                            moving=[True, True, False, True])

            data = build.collect(build.scan(self.config, root), None, rows_of)

            self.assertEqual(data['candidate']['light']['moving'], [True, True, False])

    def test_只有淺色錄影時不會憑空做出深色(self):
        with tempfile.TemporaryDirectory() as root:
            write_recording(root, 'candidate-light', ['長出'] * 3, [0.4, 4.5, 0.2])

            data = build.collect(build.scan(self.config, root), None, rows_of)

            self.assertEqual(sorted(data['candidate']), ['light'])

    def test_少了淺色錄影就停下來(self):
        with tempfile.TemporaryDirectory() as root:
            write_recording(root, 'candidate-dark', ['呼吸'] * 5, [1, 2, 3, 4, 5])

            with self.assertRaises(SystemExit):
                build.scan(self.config, root)


if __name__ == '__main__':
    unittest.main()
