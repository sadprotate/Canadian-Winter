# Canadian Winter — Game Overview

This file describes how the game is meant to play. "What's in the game now" at the bottom describes what's actually built. If the game doesn't match this file, don't change the game to match unless a task asks for it. Note the difference under `## Issues` in the round's STATUS.md.

## The idea

A satisfying first-person 3D snow-removal game where you have to make it through a full Canadian winter. Clearing snow is easy and satisfying, but every pile you make stays there: where you put the snow today becomes tomorrow's problem. As the snowbanks grow, finding somewhere to put the snow, and a way to move it, becomes the real challenge.

## How it should feel

- Clearing and moving snow feels satisfying. This matters more than anything else.
- The snowbank problem builds up slowly and is a bit funny: you made this mess yourself.
- In survival mode, the cold is a real threat you have to plan around.

## The home

- The house is decorated and should feel like a real home: bed, TV, radio, computer, coat on a hanger, couch, table, small fireplace.
- Bed: sleep to skip to the next day. TV: day-by-day forecast. Radio: hour-by-hour forecast.
- Computer: where all the business happens: contracts (open bids and ongoing jobs), history, equipment and upgrades, properties, and paying bills.
- Two doors: one to the garage, one to the outside.
- Garage: racks and space to store equipment such as shovels, scrapers, pushers, snowblowers and four-wheelers.
- The player's truck has a snowplow.

## The tutorial (the first day)

1. The player wakes up in their bedroom, beside the bed. A snowstorm has just passed, and the snow on the ground slows walking.
2. The garage door is locked (the keys are missing), and so is the computer. The only way forward is the front door.
3. Beside the front door, a picture shows the player with a shovel next to their plow truck, from when they launched the business. It hints at where the shovel is.
4. Outside: the truck on the left (locked), the mailbox, and Jerry, the neighbor, standing across the street. The keys are hidden beside the tree. The shovel is buried in snow on the far side of the truck. The tutorial can be finished without the shovel.
5. The mailbox holds an electricity bill due December 15. If it isn't paid, the house loses power and the player freezes (see Modes). Opening the mailbox starts Jerry calling "Hey, help, over here!" on repeat until the player goes to him.
6. Jerry needs his pathway cleared to reach his mailbox for his medication, and offers $50 up front. His pathway is outlined. The player clears it by hand or with the shovel.
7. The job should take most of the day: roughly until 5 p.m. with the shovel, close to 9 p.m. by hand. The player should watch the cold meter drop and start to wonder about getting home.
8. When the pathway is clear, Jerry thanks the player and brings them inside to warm up. He shows them what they need to know, including every tab of the computer and how contracts and bidding work.
9. Finally, Jerry mentions he saw something shiny beside the player's tree before the storm. The player digs out the keys, which unlock the garage and the truck. The computer is unlocked. The tutorial ends here.

## Contracts and reputation

- Contracts are posted during the day, and players bid on them. Computer-controlled bidders bid too, so the player can be outbid. The player sees whether they're currently the lowest bidder. Bids close at 9 p.m., and the lowest bid wins.
- Not built yet: right now the player negotiates a price with the customer instead. That will be replaced by the bidding above in a future polish. Don't change it unless a task asks for it, and don't list it as an issue.
- A player can win as many contracts as they want, but each one must be completed within 24 hours.
- Completing a contract pays money and raises reputation. Missing one lowers reputation.
- Every job area is outlined. When it's 90% clear, it auto-completes to 100% with a clean, satisfying finish.
- Money pays for tool upgrades, equipment (up to bigger machines like tractors), property and bills.
- Reputation unlocks bigger work: residential driveways and pathways first, then commercial jobs (the church, the school, the department store, etc.), then city work (streets and sidewalks).

## The daily loop

Bid on contracts → sleep → wake up and check the weather → do the contracts you won → bid again. When it snows, players usually wait for it to stop before clearing, though they can try to keep up while it's still snowing. Over the winter, the player upgrades equipment, buys property and bigger machines, and keeps the bills paid.

## The winter

- A season runs from December 1 to April 1. Getting through one full winter completes the game.
- December starts milder. By the end of January and through February, it's a full Canadian winter.
- Snow builds up all winter. It never melts on its own until April 1, so by the end of winter the snowbanks are huge. The melting pad lets the player melt snow before then.
- Players can keep going after the first winter. Each year's winter is harder than the last, and there's a record for how many years you've lasted.
- Rare, unpredictable events (harsh snowstorms, blizzards, others to come) can snow you in.

## Modes

- Fun mode: no cold.
- Survival mode: a cold meter. Some days are colder than others. The goal is never to get frozen out.
- The player freezes when the cold meter runs out (for example, caught outside by a snowstorm) or when the house loses power because the electricity bill wasn't paid. A frozen player wakes up at the main menu and can reload that day. It isn't a full reset, but the day is lost.

## Design rules (don't change these without asking me)

- Removing snow must feel satisfying.
- Snow never melts on its own before April 1. It only goes away when the player deals with it, for example with the melting pad or the dump truck. Snowbanks are the core challenge, not a side effect to clean up.
- Winters get harder through the season and from year to year.
- Normal snowfall can be planned for by following the weather. Only the rare events are unpredictable.
- Bids close at 9 p.m., the lowest bid wins, and won contracts must be completed within 24 hours.
- Reputation unlocks work in this order: residential, then commercial, then city.
- Fun mode never has the cold.
- Freezing costs the player the day, not the whole game.
- The tutorial follows the steps above, in that order.
- New things match the look and feel already in the game.

## What's in the game now

<!-- Ask Opus: "Fill in the 'What's in the game now' section of GAME.md from the code: the main systems and features, one line each, with a link to each feature's doc in docs/features/ where one exists." Claude keeps this section up to date after each polish. -->

- The truck and its plow: a new game starts with the player's pickup truck with its front plow in the driveway, locked until the keys are found. With the blade up it drives through deep snow like a pickup; with the blade down it plows. The plow isn't sold. ([vehicles](docs/features/vehicles.md))
- The blade keys: Up / Down raise and lower the blade on every plow; reversing with the blade down drags snow back (back-drag). All keys are rebindable. ([vehicles](docs/features/vehicles.md), [controls](docs/features/controls.md))
