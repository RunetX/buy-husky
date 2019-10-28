Function JSON2Structure(JSONString)
	
	JSONReader = New JSONReader;
	JSONReader.SetString(JSONString);
	structure = ReadJSON(JSONReader, False);
	JSONReader.Close();
	Return structure;
	
EndFunction

Function structure2JSON(structure)
	
	JSONWriter	= New JSONWriter;
	JSONWriter.SetString();
	WriteJSON(JSONWriter, structure);
	Return JSONWriter.Close(); 
	
EndFunction

Function readSession(userId)
	
	sessionQuery = New Query("SELECT
	                          |	sessionStorage.suggests AS suggests
	                          |FROM
	                          |	InformationRegister.sessionStorage AS sessionStorage
	                          |WHERE
	                          |	sessionStorage.userId = &userId");
	sessionQuery.SetParameter("userId", userId);
	sessionSelection = sessionQuery.Execute().Select();
	sessionSelection.Next();
	Return sessionSelection.suggests;
	
EndFunction

Procedure saveSession(userId, suggests)
	
	manager = InformationRegisters.sessionStorage.CreateRecordSet();
	filter = manager.Filter;
	filter.userId.Set(userId);
	manager.Read();
	
	If manager.Count() = 0 Then
		aRecord = manager.Add();		
		aRecord.userId = userId;
	Else
		aRecord = manager[0];
	EndIf;
	
	aRecord.suggests = suggests;	
	manager.Write();
	
EndProcedure

Function checkAuthorization(HTTPRequest)
	
	authorization = HTTPRequest.Headers.Get("Authorization");
	
	If ValueIsFilled(authorization) Then
		authParts = StrSplit(authorization, " ");
		token = authParts[1];
		
		Return token;
	Else
		Return Undefined;
	EndIf;
	
EndFunction

// Функция получает тело запроса и возвращает ответ.
Function requestProcessing(HTTPRequest) Export
		
	requestBody = HTTPRequest.GetBodyAsString();
	request 	= JSON2Structure(requestBody);
		
	WriteLogEvent("Request",,, requestBody);
	
	response = New Structure("version, session",
							request.version,
							request.session);
	token = checkAuthorization(HTTPRequest);

	If ValueIsFilled(token) Then
		
		response.Insert("response", New Structure("end_session", False));
		handleDialog(request, response, token);
		
	Else
	
		response.Insert("start_account_linking", New Structure());
		
	EndIf;
	
	responseBody = structure2JSON(response);
	WriteLogEvent("Response",,, responseBody);
	                                         
	HTTPResponse = New HTTPServiceResponse(200);
	HTTPResponse.Headers.Insert("Content-Type","application/json; charset=utf-8");
	HTTPResponse.SetBodyFromString(responseBody, TextEncoding.UTF8, ByteOrderMarkUse.DontUse);
		
	Return HTTPResponse;
	
EndFunction

Function checkToken(token)
	
	checkConnection = New HTTPConnection("login.yandex.ru",,,,,,New OpenSSLSecureConnection());
	checkHeaders	= New Map;
	checkHeaders.Insert("Authorization", "OAuth " + token);
	checkRequest 	= New HTTPRequest("info", checkHeaders);
	checkResponse 	= checkConnection.Get(checkRequest);
	
	If checkResponse.StatusCode = 200 Then
		
		Return JSON2Structure(checkResponse.GetBodyAsString());
		
	Else
		
		// Не авторизован (как правило 401)
		Return Undefined;
		
	EndIf;
	
EndFunction

// Процедура для непосредственной обработки диалога.
Procedure handleDialog(req, res, token)
	
	userId = req.session.user_id;
	
	// Это новый пользователь.
    // Инициализируем сессию и поприветствуем его.
	If req.session.new OR req.Property("account_linking_complete_event") Then
		
		userInfo = checkToken(token);
		
		If ValueIsFilled(userInfo) Then
		
			saveSession(userId, "Не хочу.|Не буду.|Отстань!");		            
			res.response.Insert("text", "Привет, " + userInfo.first_name + "! Купи Лайку!");
			res.response.Insert("buttons", getSuggests(userId));
			
		Else
			
			res.response.Insert("text", "Приложение Изи Клауд не авторизовано. Для продолжения необходимо предоставить доступ.");
			
		EndIf;
		
		Return;
		
	EndIf;
	                             
	// Обрабатываем ответ пользователя.
	If StrFind("ладно куплю покупаю хорошо", Lower(req.request.original_utterance)) > 0 Then
        
        // Пользователь согласился, прощаемся.
        res.response.Insert("text", "Лайку можно найти на Изи Клауд! https://izi.cloud");
		res.response.end_session = True;
        Return;
		
	EndIf;

    // Если нет, то убеждаем его купить Лайку!
    res.response.Insert("text", "Все говорят " + req.request.original_utterance + ", а ты купи Лайку!");
    res.response.Insert("buttons", getSuggests(userId));
	
EndProcedure

Function getSuggests(userId)
	
	i 			= 0;
	session 	= readSession(userId);	
	suggests 	= New Array;
	newSuggests = New Array;
	
	For each suggest In StrSplit(session, "|", False) Do
		
		// Выбираем две первые подсказки из массива.
		If i < 2 Then
			suggests.Add(New Structure("title, hide", suggest, True));
		EndIf;
		
		// Убираем первую подсказку, чтобы подсказки менялись каждый раз.
		If i > 0 Then
			newSuggests.Add(suggest);
		EndIf;
		
		i = i + 1;
		
	EndDo;
	
	saveSession(userId, StrConcat(newSuggests, "|"));
	
	// Если осталась только одна подсказка, предлагаем подсказку
    // со ссылкой на Яндекс.Маркет.
    If suggests.Count() < 2 Then
        suggests.Add(New Structure("title, url, hide", "Ладно", 
		"https://izi.cloud/", True));
	EndIf;
	
    Return suggests;
	
EndFunction