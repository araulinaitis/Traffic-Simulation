classdef Highway < handle
    properties
        numLanes
        lanes % will have n + 1 lanes.  The last lane is the on/offramp lane
        newCarQueue
        laneLength
        fig;
    end
    
    methods
        function obj = Highway(numLanes, numCars, laneLength)
            
            obj.fig = figure();
            axis([-3.7, (numLanes + 1) * 3.7 + 3.7, -20, 20 + laneLength]);
            set(gca, 'Position', [0.5, 0.1, 0.4, 0.8]);
            set(gca, 'ButtonDownFcn', @obj.clearReadouts);
            % axis equal
            
            obj.laneLength = laneLength;
            obj.numLanes = numLanes + 1;
            obj.lanes = Lane.empty;
            for i = 1:(numLanes + 1)
                obj.lanes(i) = Lane(i, laneLength);
            end
            obj.newCarQueue = numCars;
        end
        
        function clearReadouts(obj, ~, ~)
           for i = 1:obj.numLanes
              obj.lanes(i).clearReadouts; 
           end
        end
        
        function update(obj, dt)
            if obj.newCarQueue
                obj.introduce;
            end
            
            % update cars in each lane
            for i = 1:obj.numLanes
                obj.lanes(i).update(dt);
            end
            
            % janky, but it should work.  Look through each car and move it to the next lane if its
            % no longer in a lane
            for i = 1:obj.numLanes
                changeCars = obj.lanes(i).checkLane;
                for j = 1:length(changeCars)
                    obj.lanes(changeCars(j).laneNum).insertCar(changeCars(j));
                end
            end
            
            % check lanes to see if any cars need to wrap
            for i = 1:obj.numLanes
                obj.lanes(i).checkWrap;
            end
        end
        
        function introduce(obj)
            % add car at onramp, don't add a new car until the last car has exited the onramp (maybe
            % change later)
            if obj.lanes(end).numCars == 0
                obj.lanes(end).addNewCar(0);
                obj.newCarQueue = obj.newCarQueue - 1;
            end
        end
        
    end
end