TOOL.Category = "Инструмент Маршрутного Телевидения"
TOOL.Name = "RouteTelevision Tool"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ManualPlacement = TOOL.ManualPlacement or {}

-- Функции для работы с владельцами
local function GetEntityOwner(ent)
    if not IsValid(ent) then return nil end
    return ent:GetNWEntity("RouteTV_Owner")
end

local function SetEntityOwner(ent, owner)
    if not IsValid(ent) or not IsValid(owner) then return end
    ent:SetNWEntity("RouteTV_Owner", owner)
end

-- Шаблоны
local TelevisionTemplates = {
    ["trolleybus_ent_aksm321"] = {
        name = "Шаблон для AKSM 321",
        screens = {
            Front_Position = {
                {pos = Vector(100, 0, 39.5), ang = Angle(0, 180, 0)}
            }
        }
    },
    ["trolleybus_ent_aksm321n"] = {
        name = "Шаблон для AKSM 321 new",
        screens = {
            Front_Position = {
                {pos = Vector(300, 0, 125), ang = Angle(0, 0, 0)},
                {pos = Vector(160, 0, 125), ang = Angle(0, 0, 0)}
            },
            Rear_Position = {
                {pos = Vector(-210, 0, 125), ang = Angle(0, 180, 0)}
            }
        }
    },
    ["trolleybus_ent_aksm333"] = {
        name = "Шаблон для AKSM 333",
        screens = {
            Front_Position = {
                {pos = Vector(320, 0, 130), ang = Angle(0, 0, 0)},
                {pos = Vector(180, 0, 130), ang = Angle(0, 0, 0)}
            },
            Rear_Position = {
                {pos = Vector(-350, 0, 130), ang = Angle(0, 180, 0), trailer = true},
                {pos = Vector(-480, 0, 130), ang = Angle(0, 180, 0), trailer = true}
            }
        }
    }
}

if SERVER then
    util.AddNetworkString("RouteTV_ShowChoiceMenu")
    util.AddNetworkString("RouteTV_OpenEditor")
    util.AddNetworkString("RouteTV_RemoveAll")
    util.AddNetworkString("RouteTV_StartManualPlacement")
    util.AddNetworkString("RouteTV_SpawnManualTelevision")
    util.AddNetworkString("RouteTV_RequestUseTemplate")
    util.AddNetworkString("RouteTV_SaveTemplate")
end

-- Функции для работы с шаблонами
local function SaveTemplate(class, name, screens)
    TelevisionTemplates[class] = {
        name = name,
        screens = screens
    }
end

function TOOL:LeftClick(trace)
    local ply = self:GetOwner()
    local ent = trace.Entity
    if not IsValid(ent) then return false end

    -- Режим ручной установки
    if ply.RouteTVTarget and IsValid(ply.RouteTVTarget) then
        local parent = ply.RouteTVTarget

        if ent ~= parent then
            ply:ChatPrint("[RouteTV] Кликайте по выбранному объекту.")
            return false
        end

        local television = ents.Create("route_television")
        if not IsValid(television) then return false end

        local localPos = parent:WorldToLocal(trace.HitPos)
        local localAng = Angle(0, ply:EyeAngles().y - parent:GetAngles().y, 0)

        television:SetModel("route_television/models/gemp/route_television/Television_v1.mdl")
        television:SetPos(trace.HitPos)
        television:SetAngles(localAng)
        television:Spawn()
        television:Activate()
        television:SetParent(parent)
        SetEntityOwner(television, GetEntityOwner(parent) or ply)

        ply:ChatPrint("[RouteTV] Монитор добавлен на позицию: " .. tostring(localPos))
        return true
    end

    -- Проверка класса транспорта
    local class = ent:GetClass()

    ply:ChatPrint("[RouteTV] Вы выбрали транспорт: " .. class)

    -- Назначение владельца если его ещё нет
    if not IsValid(GetEntityOwner(ent)) then
        SetEntityOwner(ent, ply)
    end

    -- Всегда показываем меню, независимо от наличия шаблона
    net.Start("RouteTV_ShowChoiceMenu")
        net.WriteEntity(ent)
        net.WriteString(class)
    net.Send(ply)

    return true
end

-- Применение шаблона
net.Receive("RouteTV_RequestUseTemplate", function(_, ply)
    local ent = net.ReadEntity()
    local class = net.ReadString()
    local positionType = net.ReadString() or nil

    if not IsValid(ent) then
        ply:ChatPrint("[Ошибка] Объект недоступен.")
        return
    end

    if GetEntityOwner(ent) ~= ply then
        ply:ChatPrint("[Ошибка] Этот объект вам не принадлежит.")
        return
    end

    local template = TelevisionTemplates[class]
    if not template then
        ply:ChatPrint("[Ошибка] Шаблон не найден.")
        return
    end

    -- Получаем трейлер
    local trailer = ent.GetTrailer and ent:GetTrailer() or nil

    -- Проверка на наличие уже установленных мониторов
    local function CountTelevisions(parent)
        local count = 0
        for _, child in ipairs(parent:GetChildren()) do
            if IsValid(child) and child:GetClass() == "route_television" then
                count = count + 1
            end
        end
        return count
    end

    local totalTelevisions = CountTelevisions(ent)
    if IsValid(trailer) then
        totalTelevisions = totalTelevisions + CountTelevisions(trailer)
    end

    if totalTelevisions > 0 then
        ply:ChatPrint("[Ошибка] На этом объекте уже установлены мониторы (" .. totalTelevisions .. ").")
        return
    end

    ply:ChatPrint("[RouteTV] Применён шаблон: " .. template.name)

    -- Определяем какие экраны использовать
    local screensToUse = positionType and template.screens[positionType] or template.screens

    for _, screen in ipairs(screensToUse) do
        local parent = screen.trailer and trailer or ent
        
        if IsValid(parent) then
            local television = ents.Create("route_television")
            if not IsValid(television) then continue end

            television:SetModel("route_television/models/gemp/route_television/Television_v1.mdl")
            television:SetPos(parent:LocalToWorld(screen.pos))
            television:SetAngles(parent:LocalToWorldAngles(screen.ang))
            television:Spawn()
            television:Activate()
            television:SetParent(parent)
            SetEntityOwner(television, ply)

            ply:ChatPrint(string.format("[RouteTV] Установлен на %s: %s", 
                screen.trailer and "трейлере" or "автобусе", 
                tostring(screen.pos)))
        else
            ply:ChatPrint("[Предупреждение] Трейлер не найден для установки монитора")
        end
    end
end)

-- Удаление всех мониторов
net.Receive("RouteTV_RemoveAll", function(_, ply)
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end

    if GetEntityOwner(ent) ~= ply then
        ply:ChatPrint("[Ошибка] Этот объект вам не принадлежит.")
        return
    end

    local removed = 0
    
    -- Удаляем с основного автобуса
    for _, television in ipairs(ents.FindByClass("route_television")) do
        if television:GetParent() == ent then
            television:Remove()
            removed = removed + 1
        end
    end
    
    -- Удаляем с трейлера
    local trailer = ent.GetTrailer and ent:GetTrailer() or nil
    if IsValid(trailer) then
        for _, television in ipairs(ents.FindByClass("route_television")) do
            if television:GetParent() == trailer then
                television:Remove()
                removed = removed + 1
            end
        end
    end

    ply:ChatPrint("[RouteTV] Удалено мониторов: " .. removed)
end)

-- Установка вручную
net.Receive("RouteTV_SpawnManualTelevision", function(_, ply)
    local ent = net.ReadEntity()
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    local trailer = net.ReadBool()

    if not IsValid(ent) then return end

    if GetEntityOwner(ent) ~= ply then
        ply:ChatPrint("[Ошибка] Этот объект вам не принадлежит.")
        return
    end

    local parent = ent
    if trailer then
        parent = ent.GetTrailer and ent:GetTrailer() or nil
        if not IsValid(parent) then
            ply:ChatPrint("[Ошибка] Трейлер не найден!")
            return
        end
    end

    local television = ents.Create("route_television")
    if not IsValid(television) then return end

    television:SetModel("route_television/models/gemp/route_television/Television_v1.mdl")
    television:SetPos(parent:LocalToWorld(pos))
    television:SetAngles(parent:LocalToWorldAngles(ang))
    television:Spawn()
    television:Activate()
    television:SetParent(parent)
    SetEntityOwner(television, ply)

    ply:ChatPrint("[RouteTV] Монитор установлен вручную.")
end)

-- Сохранение шаблона
net.Receive("RouteTV_SaveTemplate", function(_, ply)
    local ent = net.ReadEntity()
    local class = net.ReadString()
    local name = net.ReadString()
    local screens = net.ReadTable()

    if not IsValid(ent) then return end

    if GetEntityOwner(ent) ~= ply then
        ply:ChatPrint("[Ошибка] Этот объект вам не принадлежит.")
        return
    end

    SaveTemplate(class, name, screens)
    ply:ChatPrint("[RouteTV] Шаблон сохранён: " .. name)
end)

-- Клиентская часть
if CLIENT then
    net.Receive("RouteTV_ShowChoiceMenu", function()
        local ent = net.ReadEntity()
        local class = net.ReadString()
        if not IsValid(ent) then return end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Выбор действия для " .. class)
        frame:SetSize(350, 230)
        frame:Center()
        frame:MakePopup()

        local label = vgui.Create("DLabel", frame)
        label:SetText("Выберите действие:")
        label:SizeToContents()
        label:SetPos(15, 35)

        -- Получаем текущий шаблон
        local template = TelevisionTemplates[class]
        local hasTemplate = template ~= nil
        local hasPositions = hasTemplate and (template.screens.Front_Position or template.screens.Rear_Position)
        
        -- Переменные для хранения выбора
        local selectedPosition
        local comboBox

        -- Создаем комбобокс только если есть позиции
        if hasPositions then
            local posLabel = vgui.Create("DLabel", frame)
            posLabel:SetText("Выберите расположение:")
            posLabel:SizeToContents()
            posLabel:SetPos(15, 155)

            comboBox = vgui.Create("DComboBox", frame)
            comboBox:SetPos(15, 175)
            comboBox:SetSize(320, 25)
            
            -- Добавляем доступные позиции
            if template.screens.Front_Position then
                comboBox:AddChoice("Передняя часть", "Front_Position")
            end
            
            if template.screens.Rear_Position then
                comboBox:AddChoice("Задняя часть", "Rear_Position")
            end
            
            -- Устанавливаем переднюю часть по умолчанию, если она есть
            if template.screens.Front_Position then
                comboBox:ChooseOptionID(1)
                selectedPosition = "Front_Position"
            elseif template.screens.Rear_Position then
                comboBox:ChooseOptionID(1)
                selectedPosition = "Rear_Position"
            end
            
            comboBox.OnSelect = function(_, index, value, data)
                selectedPosition = data
            end
        end

        local btnTemplate = vgui.Create("DButton", frame)
        btnTemplate:SetText("Использовать шаблон")
        btnTemplate:SetSize(320, 25)
        btnTemplate:SetPos(15, 65)
        btnTemplate.DoClick = function()
            if not hasTemplate then
                LocalPlayer():ChatPrint("[Ошибка] Шаблон для этого транспорта не найден!")
                return
            end
            
            if hasPositions and not selectedPosition then
                LocalPlayer():ChatPrint("[Ошибка] Сначала выберите расположение!")
                return
            end

            net.Start("RouteTV_RequestUseTemplate")
                net.WriteEntity(ent)
                net.WriteString(class)
                if hasPositions then net.WriteString(selectedPosition) end
            net.SendToServer()
            frame:Close()
        end
        
        -- Делаем кнопку серой если шаблона нет
        if not hasTemplate then
            btnTemplate:SetEnabled(false)
            btnTemplate:SetTooltip("Шаблон для этого транспорта не найден")
        end

        local btnManual = vgui.Create("DButton", frame)
        btnManual:SetText("Настроить с нуля")
        btnManual:SetSize(320, 25)
        btnManual:SetPos(15, 95)
        btnManual.DoClick = function()
            frame:Close()
            OpenManualEditor(ent, class)
        end

        local btnRemove = vgui.Create("DButton", frame)
        btnRemove:SetText("Удалить все мониторы")
        btnRemove:SetSize(320, 25)
        btnRemove:SetPos(15, 125)
        btnRemove.DoClick = function()
            net.Start("RouteTV_RemoveAll")
                net.WriteEntity(ent)
            net.SendToServer()
            frame:Close()
        end
        
        -- Увеличиваем высоту фрейма если есть позиции для выбора
        if hasPositions then
            frame:SetHeight(230)
        else
            frame:SetHeight(170)
        end
    end)

    -- Функция для открытия редактора ручной настройки
    function OpenManualEditor(ent, class)
        local frame = vgui.Create("DFrame")
        frame:SetTitle("Ручная настройка мониторов")
        frame:SetSize(800, 600)
        frame:Center()
        frame:MakePopup()
        frame:SetKeyboardInputEnabled(false)
      
        -- Панель для списка мониторов
        local leftPanel = vgui.Create("DPanel", frame)
        leftPanel:Dock(LEFT)
        leftPanel:SetWidth(200)
        leftPanel:DockMargin(5, 5, 5, 5)

        -- Панель для настроек выбранного монитора
        local rightPanel = vgui.Create("DPanel", frame)
        rightPanel:Dock(FILL)
        rightPanel:DockMargin(5, 5, 5, 5)

        -- Список мониторов
        local televisionList = vgui.Create("DListView", leftPanel)
        televisionList:Dock(FILL)
        televisionList:AddColumn("Мониторы")
        televisionList:SetMultiSelect(false)

        -- Кнопка добавления нового монитора
        local btnAdd = vgui.Create("DButton", leftPanel)
        btnAdd:Dock(BOTTOM)
        btnAdd:SetText("Добавить")
        btnAdd:DockMargin(0, 5, 0, 0)
        
        -- Переменные для хранения данных
        local currentTelevision = nil
        local televisionData = {}
        local televisionCount = 0

        btnAdd.DoClick = function()
            televisionCount = televisionCount + 1
            local id = "TV_" .. televisionCount
            televisionList:AddLine(id)
            local line = televisionList:GetLine(televisionList:GetSortedID(televisionCount))
            televisionList:SelectItem(line)
            UpdateRightPanel(rightPanel, ent, class, id, televisionList, televisionData)
        end

        -- Функция обновления правой панели
        local function UpdateRightPanel(panel, ent, class, id, list, dataTable)
            panel:Clear()

            currentTelevision = id
            televisionData[id] = televisionData[id] or {
                pos = Vector(0, 0, 0),
                ang = Angle(0, 0, 0),
                trailer = false
            }

            local data = televisionData[id]

            -- Настройка позиции
            local posX = vgui.Create("DNumSlider", panel)
            posX:Dock(TOP)
            posX:SetText("Позиция X")
            posX:SetMinMax(-500, 500)
            posX:SetDecimals(2)
            posX:SetValue(data.pos.x)
            posX:DockMargin(5, 5, 5, 0)
            posX.OnValueChanged = function(_, val)
                data.pos.x = val
            end

            local posY = vgui.Create("DNumSlider", panel)
            posY:Dock(TOP)
            posY:SetText("Позиция Y")
            posY:SetMinMax(-500, 500)
            posY:SetDecimals(2)
            posY:SetValue(data.pos.y)
            posY:DockMargin(5, 5, 5, 0)
            posY.OnValueChanged = function(_, val)
                data.pos.y = val
            end

            local posZ = vgui.Create("DNumSlider", panel)
            posZ:Dock(TOP)
            posZ:SetText("Позиция Z")
            posZ:SetMinMax(-500, 500)
            posZ:SetDecimals(2)
            posZ:SetValue(data.pos.z)
            posZ:DockMargin(5, 5, 5, 0)
            posZ.OnValueChanged = function(_, val)
                data.pos.z = val
            end

            -- Настройка угла
            local angP = vgui.Create("DNumSlider", panel)
            angP:Dock(TOP)
            angP:SetText("Угол Pitch")
            angP:SetMinMax(-180, 180)
            angP:SetDecimals(0)
            angP:SetValue(data.ang.p)
            angP:DockMargin(5, 5, 5, 0)
            angP.OnValueChanged = function(_, val)
                data.ang.p = val
            end

            local angY = vgui.Create("DNumSlider", panel)
            angY:Dock(TOP)
            angY:SetText("Угол Yaw")
            angY:SetMinMax(-180, 180)
            angY:SetDecimals(0)
            angY:SetValue(data.ang.y)
            angY:DockMargin(5, 5, 5, 0)
            angY.OnValueChanged = function(_, val)
                data.ang.y = val
            end

            local angR = vgui.Create("DNumSlider", panel)
            angR:Dock(TOP)
            angR:SetText("Угол Roll")
            angR:SetMinMax(-180, 180)
            angR:SetDecimals(0)
            angR:SetValue(data.ang.r)
            angR:DockMargin(5, 5, 5, 0)
            angR.OnValueChanged = function(_, val)
                data.ang.r = val
            end

            -- Кнопка для трейлера
            local hasTrailer = ent.GetTrailer and IsValid(ent:GetTrailer())
            if hasTrailer then
                local btnTrailer = vgui.Create("DButton", panel)
                btnTrailer:Dock(TOP)
                btnTrailer:SetText(data.trailer and "На трейлере (ON)" or "На трейлере (OFF)")
                btnTrailer:DockMargin(5, 5, 5, 0)
                btnTrailer.DoClick = function()
                    data.trailer = not data.trailer
                    btnTrailer:SetText(data.trailer and "На трейлере (ON)" or "На трейлере (OFF)")
                end
            end

            -- Кнопка удаления
            local btnDelete = vgui.Create("DButton", panel)
            btnDelete:Dock(TOP)
            btnDelete:SetText("Удалить")
            btnDelete:SetColor(Color(255, 50, 50))
            btnDelete:DockMargin(5, 5, 5, 0)
            btnDelete.DoClick = function()
                for k, line in pairs(list:GetLines()) do
                    if line:GetColumnText(1) == id then
                        list:RemoveLine(k)
                        televisionData[id] = nil
                        panel:Clear()
                        break
                    end
                end
            end

            -- Кнопка сохранения
            local btnSave = vgui.Create("DButton", panel)
            btnSave:Dock(BOTTOM)
            btnSave:SetText("Сохранить и установить")
            btnSave:DockMargin(5, 5, 5, 0)
            btnSave.DoClick = function()
                net.Start("RouteTV_SpawnManualTelevision")
                    net.WriteEntity(ent)
                    net.WriteVector(data.pos)
                    net.WriteAngle(data.ang)
                    net.WriteBool(data.trailer)
                net.SendToServer()
            end

            -- Кнопка сохранения в шаблон
            local btnSaveTemplate = vgui.Create("DButton", panel)
            btnSaveTemplate:Dock(BOTTOM)
            btnSaveTemplate:SetText("Сохранить в шаблон")
            btnSaveTemplate:DockMargin(5, 5, 5, 0)
            btnSaveTemplate.DoClick = function()
                local name = string.Trim(string.StripChars(class, "trolleybus_ent_")) .. " (custom)"
                
                local screens = {
                    Front_Position = {},
                    Rear_Position = {}
                }
                
                -- Собираем все мониторы
                for _, line in pairs(list:GetLines()) do
                    local id = line:GetColumnText(1)
                    if televisionData[id] then
                        local data = televisionData[id]
                        local position = data.pos.x > 0 and "Front_Position" or "Rear_Position"
                        table.insert(screens[position], {
                            pos = data.pos,
                            ang = data.ang,
                            trailer = data.trailer
                        })
                    end
                end
                
                net.Start("RouteTV_SaveTemplate")
                    net.WriteEntity(ent)
                    net.WriteString(class)
                    net.WriteString(name)
                    net.WriteTable(screens)
                net.SendToServer()
                
                frame:Close()
            end
        end

        -- Обработчик выбора монитора
        televisionList.OnRowSelected = function(_, index, line)
            UpdateRightPanel(rightPanel, ent, class, line:GetColumnText(1), televisionList, televisionData)
        end

        -- Добавляем первый монитор по умолчанию
        btnAdd:DoClick()
    end
end

function TOOL:RightClick(trace)
    return false
end

function TOOL:DrawHUD()
end

function TOOL:Reload(trace)
    local ply = self:GetOwner()
    if ply.RouteTVTarget then
        ply.RouteTVTarget = nil
        ply:ChatPrint("[RouteTV] Режим ручной установки завершён.")
        return true
    end
    return false
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Description = [[Для того, чтобы настроить мониторы маршрутного телевидения нужно:
        1. Нажать на кнопку ниже 'Начать настройку'.
        2. После появления gmod_tool выбрать транспорт, наведясь и нажав левую кнопку мыши.
        3. Если на транспорт имеется готовое решение, система предложит использовать стандартное решение, которое можно будет редактировать или создать свое решение с нуля.
        4. Выставить мониторы по координатам.
        5. Пользоваться.]]
    })
end
