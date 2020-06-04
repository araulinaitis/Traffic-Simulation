classdef Lane < handle
    properties
        laneNum
        numCars = 0
        cars
        x
        length
    end
    
    methods
        
        function obj = Lane(laneNum, length)
            obj.laneNum = laneNum;
            obj.cars = Car.empty;
            obj.numCars = 0;
            obj.x = (laneNum - 1) * 3.7;
            obj.length = length;
        end
        
        function clearReadouts(obj)
           for i = 1:obj.numCars
               obj.cars(i).clearReadout;
           end
        end
        
        function update(obj, dt)
            i = 1;
            while i <= obj.numCars
                killed = obj.cars(i).decide;
                if killed
                    obj.cars(i) = [];
                    obj.numCars = obj.numCars - 1;
                else
                    i = i + 1;
                end
            end
            
            for i = 1:obj.numCars
                obj.cars(i).update(dt);
            end
            
            for i = 1:obj.numCars
                obj.cars(i).setIdx(i);
            end
            
        end
        
        function checkWrap(obj)
            % since I'm keeping the order of the cars in the array, I only need to check the first
            % car in theory.  Although if the simulation step size is too large, more than one car
            % can make it past the limit
            if obj.numCars
                while obj.cars(1).getYPos > obj.length
                    obj.cars(1).wrap(obj.length);
                    obj.cars(1).setIdx(obj.numCars);
                    obj.cars = obj.cars([2:end, 1]);
                    for j = 1:(obj.numCars - 1)
                        obj.cars(j).setIdx(j);
                    end
                end
            end
        end
        
        function addNewCar(obj, y)
            obj.cars = [obj.cars, Car(obj, y)];
            obj.numCars = obj.numCars + 1;
            obj.cars.setIdx(obj.numCars)
        end
        
        function carsOut = checkLane(obj)
            % remove any cars that aren't in this lane anymore, return list of cars that are no
            % longer in this lane (they need to be added somewhere else)
            carsOut = Car.empty;
            i = 1;
            while i <= obj.numCars
                if obj.cars(i).laneNum ~= obj.laneNum
                    carsOut = [carsOut, obj.cars(i)];
                    % reduce index of cars after this before taking the car out
                    for j = (i + 1):obj.numCars
                        obj.cars(j).setIdx(j - 1);
                    end
                    obj.cars(i) = [];
                    obj.numCars = obj.numCars - 1;
                else
                    i = i + 1;
                end
            end
        end
        
        function insertCar(obj, car)
            gapIdx = obj.getGapIdxAtY(car.getYPos);
            
            if gapIdx == -1 % lane is empty
                obj.cars = car;
                car.setIdx(1);
            elseif gapIdx == obj.numCars
                obj.cars = [obj.cars, car];
                car.setIdx(obj.numCars + 1);
            else
                obj.cars = [obj.cars(1:gapIdx), car, obj.cars((gapIdx + 1):end)];
                % set this car's index to the gap index plus 1
                car.setIdx(gapIdx + 1);
                % increment index of all cars after this car
                for i = gapIdx + 2:obj.numCars
                    car.setIdx(i);
                end
            end
            obj.numCars = obj.numCars + 1;
            
        end
        
        function out = getSpeedAtY(obj, yPos)
            % return speed at yPos of this lane.  If between two cars, should be the maximum of the two
            
            if obj.numCars == 0
                out = inf;
            elseif yPos > obj.cars(1).getYPos || yPos < obj.cars(end).getYPos
                % gap at wrap limit, so the speed will be the max of the first and last cars
                out = max([obj.cars(1).getYVel, obj.cars(end).getYVel]);
                
            else
                frontSpeed = inf;
                rearSpeed = -1;
                
                for i = 1:obj.numCars
                    if obj.cars(i).getYPos > yPos
                        frontSpeed = obj.cars(i).getYVel;
                    elseif obj.cars(i).getYPos < yPos
                        rearSpeed = obj.cars(i).getYVel;
                        break % need to break once we get to the first car behind the given y value
                    end
                end
                
                out = max([frontSpeed, rearSpeed]);
            end
            
        end
        
        function out = getGapAtY(obj, yPos)
            % return gap in [frontGap, rearGap] format at give yPos
            
            gapIdx = obj.getGapIdxAtY(yPos);
            
            if gapIdx == 0
                frontGap = obj.length - yPos + obj.cars(end).getYPos;
                rearGap = yPos - obj.cars(1).getYPos;
            elseif gapIdx == obj.numCars
                frontGap = obj.cars(end).getYPos - yPos;
                rearGap = obj.length - obj.cars(1).getYPos + yPos;
            elseif gapIdx == -1
                frontGap = inf;
                rearGap = inf;
            else
                frontGap = obj.cars(gapIdx).getYPos - yPos;
                rearGap = yPos - obj.cars(gapIdx + 1).getYPos;
            end
            
            out = [frontGap, rearGap];
            
        end
        
        function out = getMaxY(obj)
            if isempty(obj.cars)
                out = 0;
            else
                out = obj.cars(1).getYPos;
            end
        end
        
        function out = getGapIdxAtY(obj, yPos)
            % gap will be between idx and idx + 1
            
            if isempty(obj.cars)
                out = -1;
            else
                if yPos > obj.cars(1).getYPos
                    out = 0;
                elseif yPos < obj.cars(end).getYPos
                    out = obj.numCars;
                else
                    for i = 2:obj.numCars
                        if yPos < obj.cars(i - 1).getYPos && yPos > obj.cars(i).getYPos
                            out = i;
                        end
                    end
                end
            end
            if ~exist('out', 'var')
                keyboard
            end
        end
        
        function out = getFrontGap(obj, pos)
            % this is confusing because when you look at the car in front of you, you're looking at
            % its back bumper (and vice-versa).  Hopefully you get it, though
            
            frontPos = obj.cars(pos).getFrontPos; % get front bumper position of car at pos
            
            if pos == 1
                backPos = obj.cars(end).getBackPos + obj.length; % get back bumper position of car in front
            else
                backPos = obj.cars(pos - 1).getBackPos;
            end
            
            out = backPos - frontPos;
        end
        
        function out = getFrontSpeed(obj, pos)
            % return speed of car in front of car at pos
            if pos > 1
                out = obj.cars(pos - 1).getYVel;
            else
                out = inf;
            end
            
        end
        
    end
end