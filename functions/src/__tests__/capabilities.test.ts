import { capabilitiesPayload } from "../capabilities";
import { IMPLEMENTED_SKILLS } from "../companyChatCore";

describe("capabilitiesPayload", () => {
  it("returns exactly the skills this backend implements", () => {
    expect(capabilitiesPayload()).toEqual({ skills: [...IMPLEMENTED_SKILLS] });
  });

  it("names the two skills implemented today", () => {
    expect(capabilitiesPayload().skills).toEqual(["web-research", "prd-writer"]);
  });

  it("cannot drift from the array that gates behaviour", () => {
    // The reason this is an endpoint over IMPLEMENTED_SKILLS rather than a
    // hand-maintained manifest doc: a second list can disagree with the one
    // parseEnabledSkills actually enforces, which is the bug class this whole
    // pass exists to remove.
    expect(capabilitiesPayload().skills).toHaveLength(IMPLEMENTED_SKILLS.length);
  });

  it("returns a fresh array so a caller cannot mutate the constant", () => {
    const first = capabilitiesPayload().skills;
    first.push("not-a-skill");
    expect(capabilitiesPayload().skills).toEqual([...IMPLEMENTED_SKILLS]);
  });
});
