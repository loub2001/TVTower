SuperStrict
Import "Dig/base.util.color.bmx"
Import "Dig/base.util.registry.spriteloader.bmx"
Import "game.player.color.bmx"
Import "game.player.finance.bmx"
Import "game.player.difficulty.bmx"
Import "game.figure.base.bmx"
Import "game.gamerules.bmx"
Import "game.ai.base.bmx"
Import "game.gameconfig.bmx"


Type TPlayerBaseCollection
	Field players:TPlayerBase[4]
	'playerID of player who sits in front of the screen
	Field playerID:Int = 1
	Global _instance:TPlayerBaseCollection


	Function GetInstance:TPlayerBaseCollection()
		if not _instance then _instance = new TPlayerBaseCollection
		return _instance
	End Function


	Method Initialize:int()
		players = new TPlayerBase[4]
		playerID = 1
	End Method


	Method Set:int(id:int=-1, player:TPlayerBase)
		If id = -1 Then id = playerID
		if id <= 0 Then return False

		If players.length < playerID Then players = players[..id+1]
		players[id-1] = player
	End Method


	Method Get:TPlayerBase(id:Int=-1)
		If id = -1 Then id = playerID
		If Not isPlayer(id) Then Return Null

		Return players[id-1]
	End Method


	Method GetCount:Int()
		return players.length
	End Method


	Method GetObservedPlayerID:int()
		for local player:TPlayerBase = EachIn players
			if GameConfig.IsObserved( player.GetFigure() )
				return player.playerID
			endif
		Next
		return playerID
	End Method


	Method IsPlayer:Int(number:Int)
		Return (number > 0 And number <= players.length And players[number-1] <> Null)
	End Method


	Method IsLocalPlayer:Int(number:Int)
		Return number = playerID
	End Method


	Method Update()
		For local p:TPlayerBase = Eachin players
			p.Update()
		Next
	End Method
End Type

'===== CONVENIENCE ACCESSOR =====
'return collection instance
Function GetPlayerBaseCollection:TPlayerBaseCollection()
	Return TPlayerBaseCollection.GetInstance()
End Function
'return specific playerBase
Function GetPlayerBase:TPlayerBase(playerID:int=-1)
	Return TPlayerBaseCollection.GetInstance().Get(playerID)
End Function

Function GetObservedPlayerID:int()
	Return TPlayerBaseCollection.GetInstance().GetObservedPlayerID()
End Function




Type TPlayerBase {_exposeToLua="selected"}
	'playername
	Field Name:String
	'name of the channel
	Field channelname:String
	'global used ID of the player
	Field playerID:Int = 0
	'channel ID the player works for
	Field channelID:Int = 0
	'the color used to colorize symbols and figures
	Field color:TPlayerColor
	'actual number of an array of figure-images
	Field figurebase:Int = 0
	'actual figure the player uses
	Field Figure:TFigureBase {_exposeToLua}

	Field difficulty:TPlayerDifficulty {nosave}
	Field difficultyGUID:string = "normal"

	Field playerAI:TAiBase

	'type of the player, local/remote human/ai
	Field playerType:int = 0

	Field emptyProgrammeSuitcase:int = False
	Field emptyProgrammeSuitcaseTime:Long = 0
	'in which room was the programme suitcase filled the last time? 
	Field emptyProgrammeSuitcaseFromRoom:string = ""

	'times at which the player was brankrupt (game over)
	Field bankruptcyTimes:Long[]

	'1=ready, 0=not set, ...
	Field networkstate:Int = 0

	Field startDay:Int = 0

	'=== NEWS ABONNEMENTS ===
	'abonnementlevels for the newsgenres
	Field newsabonnements:Int[6]
	'maximum abonnementlevel for this day
	Field newsabonnementsDayMax:Int[] = [-1,-1,-1,-1,-1,-1]
	'when was the level set
	Field newsabonnementsSetTime:Double[6]

	'distinguishing between LOCAL and REMOTE ai allows multiple players
	'to control multiple AI without needing to share "THEIR" AI files
	'-> maybe this allows for some kind of "AI fight" (or "team1 vs team2"
	'   games)
	Const PLAYERTYPE_LOCAL_HUMAN:int = 0
	Const PLAYERTYPE_LOCAL_AI:int = 1
	Const PLAYERTYPE_REMOTE_HUMAN:int = 2
	Const PLAYERTYPE_REMOTE_AI:int = 3
	Const PLAYERTYPE_INACTIVE:int = 4


	'reset everything to base state
	Method Initialize:int()
		emptyProgrammeSuitcase = False
		emptyProgrammeSuitcaseTime = 0
		for local i:int = 0 until newsabonnements.length
			newsabonnements[i] = 0
			newsabonnementsDayMax[i] = -1
			newsabonnementsSetTime[i] = 0
		next
	End Method
		

	Method GetPlayerID:Int() {_exposeToLua}
		Return playerID
	End Method

	
	Method GetFigure:TFigureBase()
		return figure
	End Method


	Method HasMasterKey:int()
		return figure.hasMasterKey
	End Method


	'returns value boss will give as credit
	Method GetCreditAvailable:Int() {_exposeToLua}
		Return 0
	End Method


	'returns the currently taken credit
	Method GetCredit:Int(day:Int=-1) {_exposeToLua}
		Return 0
	End Method


	'returns formatted value of actual money
	Method GetMoneyFormatted:String(day:Int=-1)
		Return "0"
	End Method
	
	
	Method GetTotalNewsAbonnementFees:int() {_exposeToLua}
		return 0
	End Method
	

	'return CURRENT newsAbonnement
	Method GetNewsAbonnement:Int(genre:Int) {_exposeToLua}
		If genre > 5 Then Return 0 'max 6 categories 0-5
		'for NOW culture is current affair (until there are enough news
		'for it)
		if genre = TVTNewsGenre.CULTURE then genre = TVTNewsGenre.CURRENTAFFAIRS
		Return Self.newsabonnements[genre]
	End Method


	'return which is the highest level for the given genre today
	'(which was active for longer than X game minutes)
	'if the last time a abonnement level was set was before today
	'use the current level value
	Method GetNewsAbonnementDaysMax:Int(genre:Int) {_exposeToLua}
		If genre >= TVTNewsGenre.count or genre < 0 Then Return 0
		
		local abonnementLevel:int = GetNewsAbonnement(genre)

		'not set yet - use the current abonnement
		if newsabonnementsDayMax[genre] = -1
			SetNewsAbonnementDaysMax(genre, abonnementLevel)
		endif

		'if level of genre changed - adjust maximum
		if newsabonnementsDayMax[genre] <> abonnementLevel
			'if the "set time" is not the current day, we assume
			'the current abonnement level as maxium
			'eg.: genre set 23:50 - not catched by the "30 min check"
			'also a day change sets maximum even if level is lower than
			'maximum (which is not allowed during day to pay for the best
			'level you had this day)
			if GetWorldTime().GetDay(newsabonnementsSetTime[genre]) < GetWorldTime().GetDay()
				'NOT 0:00 (the time daily costs are computed)
				if GetWorldTime().GetDayMinute() > 0
					SetNewsAbonnementDaysMax(genre, abonnementLevel)
				EndIf
			EndIf

			'more than 30 mins gone since last "abonnement set"
			if GetWorldTime().GetTimeGone() - newsabonnementsSetTime[genre] > 30*60
				'only set maximum if the new level is higher than the
				'current days maxmimum.
				if newsabonnementsDayMax[genre] < abonnementLevel
					SetNewsAbonnementDaysMax(genre, abonnementLevel)
				EndIf
			EndIf
		EndIf

		return newsabonnementsDayMax[genre]
	End Method


	'sets the current maximum level of a news abonnement level for that day
	Method SetNewsAbonnementDaysMax:Int(genre:Int, level:int)
		If genre > 5 Then Return 0 'max 6 categories 0-5
		newsabonnementsDayMax[genre] = level
	End Method


	Method IncreaseNewsAbonnement(genre:Int) {_exposeToLua}
		SetNewsAbonnement( genre, GetNewsAbonnement(genre)+1 )
	End Method


	Method SetNewsAbonnement:int(genre:Int, level:Int, sendToNetwork:Int = True) {_exposeToLua}
		If level > GameRules.maxAbonnementLevel Then level = 0 'before: Return
		If genre > 5 Then Return False 'max 6 categories 0-5
		If newsabonnements[genre] <> level
			newsabonnements[genre] = level
			'set at which time we did this
			newsabonnementsSetTime[genre] = GetWorldTime().GetTimeGone()

			return True
		EndIf

		return False
	End Method



	Method SetStartDay:int(day:int)
		'inform finance too
		GetPlayerFinanceCollection().SetPlayerStartDay(self.playerID, day )

		startDay = Max(0, day)
		return True
	End Method


	'returns how many days later than "day zero" a player started
	Method GetStartDay:int()
		return startDay
	End Method


	Method GetBankruptcyAmount:int(untilTime:Long=-1)
		if bankruptcyTimes.length = 0 then return 0
		
		if untilTime = -1 then untilTime = GetWorldTime().GetTimeGone()

		local result:int = 0
		for local i:int = 0 until bankruptcyTimes.length
			' use "<=" to also include bankruptcy happened just in that
			' moment - or 0.xx ms ago, aka the same time
			if bankruptcyTimes[i] <= untilTime then result :+ 1
		Next
		return result
	End Method


	Method GetBankruptcyTime:int(bankruptcyNumber:int=0)
		if bankruptcyNumber < 1 or bankruptcyTimes.length < bankruptcyNumber then return -1

		return bankruptcyTimes[bankruptcyNumber-1]
	End Method
	

	'attention: when used through LUA without param, the param gets "0"
	'instead of "-1"
	Method GetMoney:Int(day:Int=-1) {_exposeToLua}
		Return 0
	End Method

	'returns the financial of the given day
	'if the day is in the future, a new finance object is created
	Method GetFinance:TPlayerFinance(day:Int=-1) {_exposeToLua}
		return GetPlayerFinance(playerID, day)
	End Method


	'loads a new figurbase and colorizes it
	Method UpdateFigureBase:int(newfigurebase:Int)
		'load configuration from registry
		Local figuresConfig:TData = TData(GetRegistry().Get("figuresConfig", new TData))
		Local playerFigures:string[] = figuresConfig.GetString("playerFigures", "").split(",")
		Local figureCount:Int = Len(playerFigures)

		'skip if no figures are available (an error ?!)
		If figureCount = 0 then return False

		'limit the figurebase to the available figures
		figurebase = MathHelper.Clamp(newfigurebase, 0, figureCount-1)

		Local newSpriteName:string = playerFigures[figurebase].trim().toLower()
		Local newSprite:TSprite = GetSpriteFromRegistry(newSpriteName)
		'skip if replacement sprite does not exist or default was returned
		If not newSprite or newSprite.GetName().toLower() <>  newSpriteName then return False

		Local oldSprite:TSprite = GetSpriteFromRegistry("Player" + Self.playerID)
		Local newImage:TImage = ColorizeImageCopy(newSprite.GetImage(), color, 0,0,0,1, 0, COLORIZEMODE_OVERLAY)
		Local figuresPack:TSpritePack = TSpritePack(GetRegistry().Get("gfx_figuresPack"))

		'clear occupied area within pixmap
		oldSprite.ClearImageData()
		'draw the new figure at that area
		DrawImageOnImage(newImage, figuresPack.image, int(oldSprite.area.GetX()), int(oldSprite.area.GetY()))
	End Method


	'colorizes a figure and the corresponding sign next to the players doors in the building
	Method RecolorFigure(newColor:TPlayerColor = Null)
		If newColor = Null Then newColor = color
		color.ownerID = 0
		color = newColor
		color.ownerID = playerID
		UpdateFigureBase(figurebase)
	End Method


	Method SetDifficulty:int(difficultyGUID:string)
		local diff:TPlayerDifficulty = GetPlayerDifficulty(difficultyGUID)
		if diff
			difficulty = diff
			self.difficultyGUID = difficultyGUID
			GetPlayerDifficultyCollection().AddToPlayer(playerID, diff)
		endif
	End Method


	Method GetDifficulty:TPlayerDifficulty()
		if not difficulty
			SetDifficulty(difficultyGUID)

			if not difficulty then Throw "TPlayerBase.GetDifficulty() failed: difficulty ~q"+difficultyGUID+"~q not found."
		endif

		return difficulty
	End Method


	'called every tick
	Method Update:Int()
	End Method


	Method Compare:Int(otherObject:Object)
		if otherObject = self then return 0
		
		Local s:TPlayerBase = TPlayerBase(otherObject)
		If s
			If s.playerID > Self.playerID Then Return 1
			If s.playerID < Self.playerID Then Return -1
		EndIf
		Return Super.Compare(otherObject)
	End Method
	

	Method IsHuman:Int()
		Return IsLocalHuman() or IsRemoteHuman()
	End Method


	Method IsLocalHuman:Int()
		Return playerID = GetPlayerBaseCollection().playerID and not playerAI
		'Return playerType = PLAYERTYPE_LOCAL_HUMAN
	End Method


	Method IsRemoteHuman:Int()
		Return playerType = TPlayerBase.PLAYERTYPE_REMOTE_HUMAN and not playerAI
	End Method


	Method IsRemoteAI:Int()
		Return playerType = TPlayerBase.PLAYERTYPE_REMOTE_AI
	End Method


	Method IsLocalAI:Int()
		Return playerType = TPlayerBase.PLAYERTYPE_LOCAL_AI
	End Method


	Method SetPlayerType(playerType:int)
		self.playerType = playerType
	End Method
	

	Method IsActivePlayer:Int()
		Return (playerID = GetPlayerBaseCollection().playerID)
	End Method


	Method IsInRoom:Int(roomName:String="") {_exposeToLua}
		return GetFigure().IsInRoom(roomName)
	End Method

	'remove this helper as soon as "player" class gets a single importable
	'file
	Method SendToBoss:Int()
		'implement in real class
	End Method
End Type