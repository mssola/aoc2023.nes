utils = require "utils"

utils.StartRun("4")

utils.MemTest("@test", {
                {0x07, "92"}, {0x08, "52"},                             -- Part 1
                {0x09, "84"}, {0x0A, "A4"}, {0x0B, "6D"}, {0x0C, "00"}  -- Part 2
})

-- The test appears to be done in a few frames. Let's run this several times
-- just in case.
for i = 0, 150, 1 do
  emu.frameadvance();
end

utils.EndRun()
