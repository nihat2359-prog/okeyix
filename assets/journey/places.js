/* Coordinates are geographic anchors; models are original architectural
   interpretations, not measured reconstruction. All dimensions in metres. */
window.JourneyPlaces = {
  cities: {
    istanbul: {id:'istanbul',name:'İstanbul',origin:[29.005,41.04],scene:'bosphorus',assets:['geography.js','models.js'],
      bridges:[[[29.032,41.048],[29.052,41.045]],[[29.055,41.091],[29.075,41.09]]],
      ferry:{anchor:[29.00243,41.02065],range:.12},
      camera:{target:[-.8,0,.3],radius:16,yaw:-.25,pitch:.9},
      places:[
        {id:'kiz',name:'Kız Kulesi',district:'Üsküdar',lon:29.0041,lat:41.0211,model:'maiden',radius:.13,yaw:2.4,pitch:.32,altitude:0},
        {id:'galata',name:'Galata Kulesi',district:'Beyoğlu',lon:28.9741,lat:41.0256,model:'galata',radius:.22,yaw:2.5,pitch:.38,altitude:35},
        {id:'ortakoy',name:'Ortaköy',district:'Beşiktaş',lon:29.0271,lat:41.0473,model:'mosque',radius:.23,yaw:2.7,pitch:.38,altitude:0},
        {id:'loti',name:'Pierre Loti',district:'Eyüpsultan',lon:28.9338,lat:41.0548,model:'terrace',radius:.21,yaw:1.2,pitch:.4,altitude:55},
        {id:'haydarpasa',name:'Haydarpaşa',district:'Kadıköy',lon:29.0186,lat:40.9969,model:'station',radius:.38,yaw:-1.3,pitch:.4,altitude:0},
        {id:'hisar',name:'Rumeli Hisarı',district:'Sarıyer',lon:29.0562,lat:41.0848,model:'fortress',radius:.38,yaw:2.4,pitch:.55,altitude:18},
      ]},
  },
};
Object.values(window.JourneyPlaces.cities).forEach(city=>city.places.forEach(place=>{place.cityId=city.id;place.nearDetail={model:place.model,loadOnFocus:true};}));
