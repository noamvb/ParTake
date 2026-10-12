class PollsMethodSection {
  const PollsMethodSection(this.title, this.blocks);
  final String title;
  final List<PollsMethodBlock> blocks;
}

class PollsMethodBlock {
  const PollsMethodBlock.paragraph(this.paragraph) : bullets = const [];
  const PollsMethodBlock.bullets(this.bullets) : paragraph = null;
  final String? paragraph;
  final List<PollsMethodBullet> bullets;
}

class PollsMethodBullet {
  const PollsMethodBullet(this.text, {this.label = '', this.bold = false});
  final String text;
  final String label;
  final bool bold;
}

const pollsMethod = <PollsMethodSection>[
  PollsMethodSection("What it shows", [
    PollsMethodBlock.paragraph(
      "Roughly how many seats each party would win if a federal election were held today, based on the latest opinion polls. It is a snapshot, not a forecast: campaigns move votes, and polls can be wrong.",
    ),
  ]),
  PollsMethodSection("1. Polls", [
    PollsMethodBlock.paragraph(
      "Every federal voting-intention poll listed by 338Canada, for Canada as a whole and for six regions: Atlantic, Quebec, Ontario, the Prairies (Manitoba and Saskatchewan), Alberta and British Columbia. Read once a day at 6:30 a.m. Ottawa time, back to the 28 April 2025 election.",
    ),
  ]),
  PollsMethodSection("2. The polling average", [
    PollsMethodBlock.paragraph("For each region:"),
    PollsMethodBlock.bullets([
      PollsMethodBullet("Each polling firm counts once, with its latest poll."),
      PollsMethodBullet("Polls older than 60 days are dropped."),
      PollsMethodBullet(
        "Bigger polls count more, but not in proportion: a poll four times the size counts twice as much.",
      ),
      PollsMethodBullet(
        "Newer polls count more: a poll's weight halves every 14 days.",
      ),
      PollsMethodBullet(
        "Daily tracking polls, which re-report overlapping days, count only for the part of the sample that is new.",
      ),
      PollsMethodBullet("Each poll is scaled so its parties add up to 100%."),
    ]),
  ]),
  PollsMethodSection("3. From the polls to each riding", [
    PollsMethodBlock.paragraph(
      "Each riding starts from its 2025 election result. If a party has gained a fifth of its support in the region since the election, its share in each of that region's ridings grows by a fifth too (proportional swing), and the riding's shares are scaled back to 100%. A party's share can at most triple. The three territories follow the national change. The People's Party and independents count as Others.",
    ),
  ]),
  PollsMethodSection("4. Seats", [
    PollsMethodBlock.paragraph(
      "The party with the highest projected share wins the riding. A majority is 172 of the 343 seats.",
    ),
  ]),
  PollsMethodSection("5. Ranges and odds", [
    PollsMethodBlock.paragraph(
      "The projection is run 10,000 times, each time with random polling error added: one nationwide error (typically about 2 points), one per region (about 3 points) and one per riding (about 5 points). The seat number shown is the middle run; the range covers the middle 80% of runs. Majority odds are the share of runs in which a party reaches 172 seats. The same day always gives the same numbers.",
    ),
    PollsMethodBlock.paragraph(
      "The trend chart uses the projection without random error, one point per day.",
    ),
  ]),
  PollsMethodSection("6. Riding status for an MP", [
    PollsMethodBlock.paragraph(
      "From the point of view of the party that holds the seat:",
    ),
    PollsMethodBlock.bullets([
      PollsMethodBullet(
        ": it keeps the seat in at least 90% of runs.",
        label: "Safe",
        bold: true,
      ),
      PollsMethodBullet(": at least 70%.", label: "Likely", bold: true),
      PollsMethodBullet(": less than 70%.", label: "At risk", bold: true),
      PollsMethodBullet(
        ": another party is projected to win.",
        label: "Projected loss",
        bold: true,
      ),
    ]),
  ]),
  PollsMethodSection("7. The weekly note", [
    PollsMethodBlock.paragraph(
      "Written automatically from the numbers by fixed rules, after each week ends (Monday to Sunday). No AI writes it.",
    ),
  ]),
  PollsMethodSection("8. How well it works", [
    PollsMethodBlock.paragraph(
      "Tested on the 2021 election: starting from the 2019 results and using only the polls from the 2021 campaign, the method picked the right winner in 301 of 338 ridings (89%). It gave the Liberals 150 seats (actual 160) and the Conservatives 115 (actual 119).",
    ),
    PollsMethodBlock.paragraph(
      "The actual Liberal, Conservative and Bloc seat counts fell inside the simulated 80% ranges. The NDP won 25 seats, below its range of 33 to 50, because the 2021 polls overstated NDP support.",
    ),
  ]),
  PollsMethodSection("9. What it leaves out", [
    PollsMethodBlock.paragraph(
      "Riding polls, candidates, incumbency, by-election swings, local campaigns and demographics. Parties strong in only a few ridings may be under- or over-counted.",
    ),
  ]),
  PollsMethodSection("10. Sources", [
    PollsMethodBlock.bullets([
      PollsMethodBullet(
        "Polls: 338Canada (338canada.com), read for personal use.",
      ),
      PollsMethodBullet("2025 results: Elections Canada."),
      PollsMethodBullet("Leader and approval polls: Wikipedia, CC BY-SA 4.0."),
      PollsMethodBullet(
        "338Canada's own seat projection is shown for comparison. It uses a different, more detailed model.",
      ),
    ]),
    PollsMethodBlock.paragraph(
      "ParTake is not affiliated with 338Canada, Elections Canada or any polling firm.",
    ),
  ]),
];
